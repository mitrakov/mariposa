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
import spray.json.{DefaultJsonProtocol, RootJsonFormat}

import java.util.concurrent.Executors
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.jdk.CollectionConverters._
import scala.util.{Failure, Success, Try}

case class HBaseDF(columns: Seq[String], data: Seq[Map[String, String]])

object HBaseDFProtocol extends DefaultJsonProtocol with SprayJsonSupport {
  implicit val dataFrameResponseFormat: RootJsonFormat[HBaseDF] = jsonFormat2(HBaseDF)
}

import HBaseDFProtocol._

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
        val fullTableName = s"$namespace:$tableName"

        val scanFuture: Future[HBaseDF] = Future {
          val table = hbaseConnection.getTable(TableName.valueOf(fullTableName))
          val scan = new Scan()

          val scanner = table.getScanner(scan)
          try {
            val rowsBuffer = scala.collection.mutable.ListBuffer[Map[String, String]]()
            val detectedColumns = scala.collection.mutable.Set[String]()

            // Añadir por defecto la columna del RowKey primario
            detectedColumns.add("rowkey")

            for (result <- scanner.asScala) {
              val rowkeyStr = Bytes.toString(result.getRow)
              val rowMap = scala.collection.mutable.Map[String, String]("rowkey" -> rowkeyStr)

              // 💡 Extraer dinámicamente las celdas sin conocer las columnas de antemano
              result.listCells().asScala.foreach { cell =>
                val qualifierStr = Bytes.toString(cell.getQualifierArray, cell.getQualifierOffset, cell.getQualifierLength)
                val valueStr     = Bytes.toString(cell.getValueArray, cell.getValueOffset, cell.getValueLength)

                rowMap.put(qualifierStr, valueStr)
                detectedColumns.add(qualifierStr)
              }
              rowsBuffer.append(rowMap.toMap)
            }

            // Ordenar las columnas para asegurar un esquema JSON limpio y predecible
            val sortedColumns = detectedColumns.toSeq.sorted
            HBaseDF(columns = sortedColumns, data = rowsBuffer.toSeq)
          } finally {
            scanner.close()
            table.close()
          }
        }

        onComplete(scanFuture) {
          case Success(dfResponse) =>
            complete(dfResponse) // Responde el DataFrame completo serializado automáticamente
          case Failure(ex) =>
            logger.error(s"Failed to extract dynamic DataFrame for $fullTableName", ex)
            complete(StatusCodes.InternalServerError, s"HBase SCAN error: ${ex.getMessage}")
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
    val future = for {
      srv <- server
      _ <- srv.terminate(2.seconds) 
    } yield {
      system.terminate()
      Try(hbaseConnection.close())
      executor.shutdown()
      logger.info("Good bye! \uD83E\uDD8B")
    }
    Await.result(future, 2.seconds) // wait graceful shutdown to complete
  }
}
