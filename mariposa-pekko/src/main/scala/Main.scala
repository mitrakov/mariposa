import hbase.DataFrameService
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory}
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.server.Directives._
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol._
import spray.json.RootJsonFormat
import java.util.concurrent.Executors
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.jdk.CollectionConverters._
import scala.util.{Failure, Success, Try}

/** Simple HTTP server to read HBase tables */
object Main extends App {
  private val logger = LoggerFactory.getLogger(Main.getClass)
  private val serverPort = sys.props.getOrElse("app.server.port", "7012").toInt
  private val hbaseConnection: Connection = ConnectionFactory.createConnection(HBaseConfiguration.create())
  private val dfService = new DataFrameService(hbaseConnection)
  private val executor = Executors.newFixedThreadPool(16)
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  implicit val ec: ExecutionContext = ExecutionContext.fromExecutor(executor)
  implicit val tableResponseFmt: RootJsonFormat[TableResponse] = jsonFormat4(TableResponse)

  // Routes
  private val routes =
    pathPrefix("v1" / "hbase") {
      path("tables") {
        get {
          logger.info("GET list all HBase tables")
          val listFuture = Future {
            hbaseConnection.getAdmin.listTableDescriptors().asScala.map(_.getTableName.getNameAsString).toList.sorted
          }

          onComplete(listFuture) {
            case Success(tablesList) =>
              logger.info(s"Result: ${tablesList.headOption} ... (${tablesList.size} tables)")
              complete(tablesList)
            case Failure(ex) =>
              logger.error(s"Error: /tables", ex)
              complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
          }
        }
      } ~ path("table" / Segment) { tableName =>
        get {
          parameters("startRow".?, "limit".as[Int].?(1000)) { (startRow, limit) =>
            val pageFuture = Future {
              dfService.fetchTablePage(tableName, startRow, limit)
            }

            onComplete(pageFuture) {
              case Success(page) =>
                logger.info(s"Result: ${page.columns} :: ${page.rows.headOption} ... (${page.rows.size} rows)")
                complete(TableResponse(tableName, page.columns, page.rows, page.nextRowKey))
              case Failure(ex) =>
                logger.error(s"Error: /table/$tableName", ex)
                complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
            }
          }
        }
      }
    }

  // Start HTTP server
  private val server = Http().newServerAt("0.0.0.0", serverPort).bind(routes)
  server.onComplete {
    case Success(binding) =>
      logger.info(s"Mariposa Web is ONLINE at http://localhost:${binding.localAddress.getPort}/")
    case Failure(e) =>
      logger.error(s"Failed to start server", e)
      cleanUp()
  }

  // add graceful shutdown hook
  sys.addShutdownHook { cleanUp() }

  /** Graceful shutdown */
  private def cleanUp(): Unit = {
    logger.info("Graceful shutdown...")
    Try(hbaseConnection.close())
    val future = for {
      srv <- server
      _ <- srv.unbind().recover {case _ => }
      _ <- srv.terminate(1.second)
    } yield {
      system.terminate()
      executor.shutdown()
      logger.info("Good bye! \uD83E\uDD8B")
    }
    Await.result(future, 2.seconds) // wait graceful shutdown to complete
  }
}

case class TableResponse(tableName: String, columns: List[String], rows: List[List[Option[String]]], nextRowKey: Option[String])
