import org.apache.hadoop.hbase.client.{Admin, Connection, ConnectionFactory, Scan}
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.hbase.{HBaseConfiguration, TableName}
import org.apache.hadoop.security.UserGroupInformation
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import org.apache.pekko.http.scaladsl.model.{ContentTypes, HttpEntity, StatusCodes}
import org.apache.pekko.http.scaladsl.server.Directives._
import org.apache.pekko.stream.OverflowStrategy
import org.apache.pekko.stream.scaladsl.Source
import org.apache.pekko.util.ByteString
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol._
import spray.json.RootJsonFormat
import java.util.Base64
import java.util.concurrent.Executors
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.jdk.CollectionConverters._
import scala.sys.process.{ProcessLogger, stringSeqToProcess}
import scala.util.{Failure, Success, Try}

/** Simple HTTP server to read HBase tables. Supports Kerberos GSSAPI */
object Main extends App {
  private val logger = LoggerFactory.getLogger(Main.getClass)
  private val loginToKerberos = sys.props.getOrElse("app.kerberos.enabled", "false").toBoolean
  private val serverPort = sys.props.getOrElse("app.server.port", "7012").toInt
  private val hbaseConfig = HBaseConfiguration.create()
  private val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)
  private val executor = Executors.newFixedThreadPool(16)
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  implicit val ec: ExecutionContext = ExecutionContext.fromExecutor(executor)
  implicit val sparkRequestFormat: RootJsonFormat[SparkRequest] = jsonFormat2(SparkRequest)

  if (loginToKerberos) {
    logger.info("Kerberos is active. Negotiating TGT...")
    val principal = sys.props.getOrElse("app.kerberos.principal", throw new Exception("Set -Dapp.kerberos.principal"))
    val keytab    = sys.props.getOrElse("app.kerberos.keytab", throw new Exception("Set -Dapp.kerberos.keytab"))
    UserGroupInformation.setConfiguration(hbaseConfig)
    UserGroupInformation.loginUserFromKeytab(principal, keytab)
  }

  // Routes
  private val routes =
    pathPrefix("v1" / "hbase") {
      path("tables") {
        get {
          logger.info("GET list all HBase tables")
          val listFuture = Future {
            val admin: Admin = hbaseConnection.getAdmin
            try { admin.listTableDescriptors().asScala.map(_.getTableName.getNameAsString).toList.sorted } finally {admin.close()}
          }

          onComplete(listFuture) {
            case Success(tablesList) =>
              logger.info(s"Result: ${tablesList.headOption} ... (${tablesList.size} tables)")
              complete(tablesList)
            case Failure(ex) =>
              logger.error("Failed to retrieve HBase tables catalog", ex)
              complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
          }
        }
      } ~ path(Segment / Segment) { (namespace, tableName) =>
        get {
          logger.info(s"GET HBase table: $namespace:$tableName")
          val scanFuture = Future {
            val table = hbaseConnection.getTable(TableName.valueOf(s"$namespace:$tableName"))
            val scanner = table.getScanner(new Scan())
            try {
              scanner.asScala.map { result =>
                val cellsMap = Option(result.listCells()).map(_.asScala).getOrElse(Nil).map { cell =>
                  val qualifierStr = Bytes.toString(cell.getQualifierArray, cell.getQualifierOffset, cell.getQualifierLength)
                  val valueStr     = Bytes.toString(cell.getValueArray,     cell.getValueOffset,     cell.getValueLength)
                  qualifierStr -> valueStr
                }.toMap

                cellsMap + ("key" -> Bytes.toString(result.getRow))
              }.toList
            } finally {
              scanner.close()
              table.close()
            }
          }

          onComplete(scanFuture) {
            case Success(list) =>
              logger.info(s"Result: ${list.headOption}... (${list.size} rows)")
              complete(list)
            case Failure(ex) =>
              logger.error(s"HBase query failed for $namespace:$tableName", ex)
              complete(StatusCodes.InternalServerError, Map("error" -> ex.getMessage))
          }
        }
      }
    } ~ path("v1" / "spark") {
      post {
        entity(as[SparkRequest]) { req =>
          logger.info(s"POST Run Spark SQL: $req")
          val sqlBase64 = Base64.getEncoder.encodeToString(req.sql.getBytes())

          val (queue, source) = Source.queue[ByteString](bufferSize = 1000, OverflowStrategy.dropTail).preMaterialize()

          Future {
            val command = Seq(
              "spark-submit",
              s"--driver-java-options=-Dapp.hbase.table=${req.hbaseTable} -Dapp.hive.sql.base64=$sqlBase64",
              "--class", "com.mitrakoff.mariposa.Hive2HBase",
              "/home/hadoop/mariposa-assembly-*.jar"
            )

            def offerLog(line: String): Unit = queue.offer(ByteString(s"$line\n"))

            val processLogger = ProcessLogger(s => offerLog(s))

            val exitCode = command ! processLogger
            offerLog(s"Finished with code: $exitCode")
            queue.complete()
          }

          complete(HttpEntity.Chunked.fromData(ContentTypes.`text/plain(UTF-8)`, source))
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

case class SparkRequest(sql: String, hbaseTable: String)
