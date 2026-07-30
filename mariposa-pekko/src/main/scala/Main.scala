import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory, Scan}
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.hbase.{HBaseConfiguration, TableName}
import org.apache.hadoop.security.UserGroupInformation
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.server.Directives._
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol
import DefaultJsonProtocol._
import SprayJsonSupport._

import java.util.concurrent.Executors
import scala.collection.mutable
import scala.collection.mutable.ListBuffer
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.jdk.CollectionConverters._
import scala.util.{Failure, Success, Try}

object Main extends App {
  private val loginToKerberos = true
  private val logger = LoggerFactory.getLogger(Main.getClass)
  private val hbaseConfig = HBaseConfiguration.create()
  private val serverPort = sys.props.getOrElse("app.server.port", "7012")
  private val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)
  private val executor = Executors.newFixedThreadPool(20)
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  implicit val ec: ExecutionContext = ExecutionContext.fromExecutor(executor)

  if (loginToKerberos) {
    logger.info("Kerberos authentication active. Negotiating TGT...")
    val principal = sys.props.getOrElse("app.security.principal", "hbase/namenode.host@MARIPOSA.COM")
    val keytab    = sys.props.getOrElse("app.security.keytab", "/etc/security/keytabs/namenode.host.keytab")
    UserGroupInformation.setConfiguration(hbaseConfig)
    UserGroupInformation.loginUserFromKeytab(principal, keytab)
  }

  // Routes
  private val routes =
    path("v1" / "hbase" / Segment / Segment) { (namespace, tableName) =>
      get {
        val scanFuture: Future[Seq[Map[String, String]]] = Future {
          logger.info(s"HBase GET: $namespace:$tableName")
          val table = hbaseConnection.getTable(TableName.valueOf(s"$namespace:$tableName"))
          val scanner = table.getScanner(new Scan())
          try {
            val rowsBuffer = ListBuffer[Map[String, String]]()

            for (result <- scanner.asScala) {
              val rowkeyStr = Bytes.toString(result.getRow)
              val rowMap = mutable.Map[String, String]("rowkey" -> rowkeyStr)

              result.listCells().asScala.foreach { cell =>
                val qualifierStr = Bytes.toString(cell.getQualifierArray, cell.getQualifierOffset, cell.getQualifierLength)
                val valueStr     = Bytes.toString(cell.getValueArray, cell.getValueOffset, cell.getValueLength)

                rowMap.put(qualifierStr, valueStr)
              }
              rowsBuffer.append(rowMap.toMap)
            }

            rowsBuffer.toSeq
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
  private val server = Http().newServerAt("0.0.0.0", serverPort.toInt).bind(routes) 
  server.onComplete {
    case Success(binding) =>
      logger.info(s"Mariposa Web is ONLINE at http://localhost:${binding.localAddress.getPort}/")
    case Failure(e) =>
      logger.error(s"Failed to start server", e)
      cleanUp()
  }

  sys.addShutdownHook { cleanUp() }

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
