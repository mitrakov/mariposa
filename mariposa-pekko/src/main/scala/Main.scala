import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.server.Directives._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.TableName
import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory, Get, Scan}
import org.apache.hadoop.hbase.util.Bytes
import org.apache.hadoop.security.UserGroupInformation
import org.slf4j.LoggerFactory

import java.util.concurrent.Executors
import scala.util.{Failure, Success}
import scala.concurrent.{ExecutionContext, Future}
import scala.jdk.CollectionConverters._
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport
import spray.json.{DefaultJsonProtocol, RootJsonFormat}

// 💡 Caso de uso para representar un registro estructurado de HBase
case class UserRecord(rowkey: String, email: String)

// 💡 Protocolo nativo de Spray JSON para habilitar el formateo automático
object UserJsonProtocol extends DefaultJsonProtocol with SprayJsonSupport {
  implicit val userRecordFormat: RootJsonFormat[UserRecord] = jsonFormat2(UserRecord)
}

import UserJsonProtocol._

object Main extends App {
  val loginToKerberos = true
  private val logger = LoggerFactory.getLogger(Main.getClass)

  logger.info("Initializing Mariposa-Pekko JSON Endpoint Server...")
  val hbaseConfig = HBaseConfiguration.create()

  // Parametrización dinámica vía System Properties
  val serverPort   = sys.props.getOrElse("app.server.port", "7012")
  val targetTable  = sys.props.getOrElse("app.hbase.table", "users")
  val columnFamily = sys.props.getOrElse("app.hbase.cf", "info")
  val qualifier    = sys.props.getOrElse("app.hbase.qualifier", "email")

  // Manejo automatizado de Kerberos / Simple Auth
  if (loginToKerberos) {
    logger.info("Kerberos authentication active. Negotiating TGT...")
    val principal = sys.props.getOrElse("app.security.principal", "hbase/namenode.host@MARIPOSA.COM")
    val keytab    = sys.props.getOrElse("app.security.keytab", "/etc/security/keytabs/namenode.host.keytab")
    UserGroupInformation.setConfiguration(hbaseConfig)
    UserGroupInformation.loginUserFromKeytab(principal, keytab)
  }

  // 1. Inicializar conexiones globales
  val hbaseConnection: Connection = ConnectionFactory.createConnection(hbaseConfig)
  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "Mariposa")
  implicit val hbaseEC: ExecutionContext = ExecutionContext.fromExecutor(Executors.newFixedThreadPool(20))

  // 2. Definición de Rutas HTTP Reactivas
  val routes =
    concat(
      // 💡 NUEVO ENDPOINT: Descargar toda la tabla como un arreglo JSON
      path("users") {
        get {
          val scanFuture: Future[Seq[UserRecord]] = Future {
            val table = hbaseConnection.getTable(TableName.valueOf(targetTable))
            val scan = new Scan()
            // Optimización de rendimiento para escaneos masivos en HBase
            scan.addFamily(Bytes.toBytes(columnFamily))
            scan.setCaching(500)

            val scanner = table.getScanner(scan)
            try {
              // Convertir el Iterador de HBase a una colección nativa de Scala
              scanner.asScala.flatMap { result =>
                val rowkeyStr = Bytes.toString(result.getRow)
                val emailBytes = result.getValue(Bytes.toBytes(columnFamily), Bytes.toBytes(qualifier))
                Option(emailBytes).map(Bytes.toString).map(emailStr => UserRecord(rowkeyStr, emailStr))
              }.toSeq
            } finally {
              scanner.close()
              table.close()
            }
          }(hbaseEC)

          onComplete(scanFuture) {
            case Success(records) =>
              // Spray JSON serializa la Seq[UserRecord] a un arreglo JSON automáticamente
              complete(records)
            case Failure(ex) =>
              logger.error("HBase massive scan failed", ex)
              complete(StatusCodes.InternalServerError, s"HBase SCAN error: ${ex.getMessage}")
          }
        }
      },

      // ENDPOINT ORIGINAL: Buscar un usuario específico por segmento
      path("user" / Segment) { userId =>
        get {
          val resultFuture: Future[Option[UserRecord]] = Future {
            val table = hbaseConnection.getTable(TableName.valueOf(targetTable))
            try {
              val getReq = new Get(Bytes.toBytes(userId))
              val result = table.get(getReq)
              if (!result.isEmpty) {
                val emailBytes = result.getValue(Bytes.toBytes(columnFamily), Bytes.toBytes(qualifier))
                Option(emailBytes).map(Bytes.toString).map(email => UserRecord(userId, email))
              } else None
            } finally {
              table.close()
            }
          }(hbaseEC)

          onComplete(resultFuture) {
            case Success(Some(record)) => complete(record) // Ahora también responde en JSON limpio
            case Success(None)         => complete(StatusCodes.NotFound, s"User $userId not found.")
            case Failure(ex)           => complete(StatusCodes.InternalServerError, ex.getMessage)
          }
        }
      }
    )

  // 3. Encender el servidor HTTP de Pekko
  val bindingFuture = Http().newServerAt("0.0.0.0", serverPort.toInt).bind(routes)
  bindingFuture.onComplete {
    case Success(binding) =>
      logger.info(s"Mariposa REST JSON service is ONLINE at http://localhost:${binding.localAddress.getPort}/")
    case Failure(e) =>
      logger.error(s"Failed to start server", e)
      cleanUp()
  }

  sys.addShutdownHook { cleanUp() }

  private def cleanUp(): Unit = {
    try { hbaseConnection.close() } catch { case _: Exception => }
    system.terminate()
    logger.info("Resources released successfully.")
  }
}
