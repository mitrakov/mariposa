import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory, Scan}
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.hbase.{HBaseConfiguration, TableName}
import org.apache.hadoop.security.UserGroupInformation
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.server.Directives._
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol._
import java.util.concurrent.Executors
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.jdk.CollectionConverters._
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

  if (loginToKerberos) {
    logger.info("Kerberos is active. Negotiating TGT...")
    val principal = sys.props.getOrElse("app.kerberos.principal", throw new Exception("Set -Dapp.kerberos.principal"))
    val keytab    = sys.props.getOrElse("app.kerberos.keytab", throw new Exception("Set -Dapp.kerberos.keytab"))
    UserGroupInformation.setConfiguration(hbaseConfig)
    UserGroupInformation.loginUserFromKeytab(principal, keytab)
  }

  // Routes
  private val routes =
    path("v1" / "hbase" / Segment / Segment) { (namespace, tableName) =>
      get {
        val scanFuture = Future {
          logger.info(s"HBase GET: $namespace:$tableName")
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
