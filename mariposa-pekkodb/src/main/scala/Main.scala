import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.server.Directives._
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol._
import spray.json.{JsValue, JsonParser, RootJsonFormat}

import java.sql.{Connection, DriverManager}
import java.util.concurrent.Executors
import scala.collection.mutable.ListBuffer
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.util.{Failure, Success, Try, Using}

object Main {
  private val logger     = LoggerFactory.getLogger(getClass)
  private val serverPort = sys.props.getOrElse("app.server.port", "7012").toInt
  private val dbUrl      = sys.props.getOrElse("app.sqlite.url", "jdbc:sqlite:planet.db")

  private val executor = Executors.newFixedThreadPool(16)
  given system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  given ec: ExecutionContext         = ExecutionContext.fromExecutor(executor)

  // Explicit given resolvers to avoid Scala 3 CollectionFormats ambiguity
  given stringListFmt:   RootJsonFormat[List[String]]        = listFormat[String]
  given stringMapFmt:    RootJsonFormat[Map[String, String]] = mapFormat[String, String]
  given pageResponseFmt: RootJsonFormat[SqlitePageResponse]  = jsonFormat3(SqlitePageResponse.apply)

  /** Opens a read-safe SQLite connection configured for concurrent WAL reads */
  private def openConnection(): Connection = {
    DriverManager.getConnection(dbUrl)
    // Using.resource(conn.createStatement()) {s => s.execute("PRAGMA journal_mode=WAL;"); s.execute("PRAGMA busy_timeout=5000;")}
  }

  /** Lists all user tables in the SQLite database */
  private def listTables(): List[String] = {
    Using.resource(openConnection()) { conn =>
      val sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      Using.resource(conn.prepareStatement(sql)) { stmt =>
        Using.resource(stmt.executeQuery()) { rs =>
          val tables = ListBuffer[String]()
          while (rs.next()) {
            tables += rs.getString("name")
          }
          tables.toList
        }
      }
    }
  }

  /** Fetches paginated JSON payloads using keyset pagination on `id` */
  private def fetchTablePage(tableName: String, startRow: Option[String], limit: Int): SqlitePageResponse = {
    val validTables = listTables().toSet
    require(validTables.contains(tableName), s"Table '$tableName' does not exist")

    Using.resource(openConnection()) { conn =>
      val sql = startRow match {
        case Some(_) => s"SELECT id, payload FROM $tableName WHERE id > ? ORDER BY id ASC LIMIT ?"
        case None    => s"SELECT id, payload FROM $tableName ORDER BY id ASC LIMIT ?"
      }

      Using.resource(conn.prepareStatement(sql)) { stmt =>
        startRow match {
          case Some(cursor) =>
            stmt.setString(1, cursor)
            stmt.setInt(2, limit)
          case None =>
            stmt.setInt(1, limit)
        }

        Using.resource(stmt.executeQuery()) { rs =>
          val payloads = ListBuffer[JsValue]()
          var lastId: Option[String] = None

          while (rs.next()) {
            lastId = Some(rs.getString("id"))
            val rawJson = rs.getString("payload")
            payloads += JsonParser(rawJson)
          }

          val nextKey = if (payloads.size == limit) lastId else None
          SqlitePageResponse(tableName, payloads.toList, nextKey)
        }
      }
    }
  }

  private val routes = {
    pathPrefix("v1" / "hbase") {                                             // TODO: rm hbase
      path("tables") {
        get {
          onComplete(Future(listTables())) {
            case Success(tablesList) =>
              logger.info(s"Result: ${tablesList.headOption} ... (${tablesList.size} tables)")
              complete(tablesList)
            case Failure(ex) =>
              logger.error("Error: /tables", ex)
              complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
          }
        }
      } ~ path("table" / Segment) { tableName =>
        get {
          parameters("startRow".?, "limit".as[Int].?(10)) { (startRow, limit) =>
            onComplete(Future(fetchTablePage(tableName, startRow, limit))) {
              case Success(page) =>
                logger.info(s"Result: $tableName (${page.rows.size} rows, nextRowKey=${page.nextRowKey})")
                complete(page)
              case Failure(ex: IllegalArgumentException) =>
                complete(StatusCodes.NotFound, Map("error" -> ex.getMessage))
              case Failure(ex) =>
                logger.error(s"Error: /table/$tableName", ex)
                complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
            }
          }
        }
      }
    }
  }

  @main def runServer(): Unit = {
    val server = Http().newServerAt("0.0.0.0", serverPort).bind(routes)
    server.onComplete {
      case Success(binding) => logger.info(s"Mariposa Web (SQLite) is ONLINE at http://localhost:${binding.localAddress.getPort}/")
      case Failure(e) => logger.error("Failed to start server", e); cleanUp(server)
    }

    sys.addShutdownHook {
      cleanUp(server)
    }
  }

  private def cleanUp(serverFuture: Future[Http.ServerBinding]): Unit = {
    logger.info("Graceful shutdown...")
    val shutdownFuture = for {
      srv <- serverFuture
      _   <- srv.unbind().recover { case _ => () }
      _   <- srv.terminate(1.second)
    } yield {
      system.terminate()
      executor.shutdown()
      logger.info("Good bye! \uD83E\uDD8B")
    }

    Try(Await.result(shutdownFuture, 2.seconds))
  }
}

case class SqlitePageResponse(tableName: String, rows: List[JsValue], nextRowKey: Option[String])
