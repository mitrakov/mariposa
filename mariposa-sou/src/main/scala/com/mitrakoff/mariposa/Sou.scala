package com.mitrakoff.mariposa

import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.server.Directives._
import org.slf4j.LoggerFactory
import spray.json.DefaultJsonProtocol._
import spray.json.RootJsonFormat
import java.io.File
import java.util.concurrent.{ConcurrentHashMap, Executors}
import scala.concurrent.duration.DurationInt
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.util.{Failure, Success, Try}

// Caso para rastrear la metadata del proceso en memoria
case class ProcessInfo(pid: Long, scriptPath: String, logFile: String, startTime: Long)
case class StatusResponse(pid: Long, status: String, script: String, logFile: String, uptimeSeconds: Long)

object Sou {
  private val logger = LoggerFactory.getLogger(getClass)
  private val serverPort = sys.props.getOrElse("app.scraper.port", "7013").toInt

  // Tabla mutable segura para hilos que guarda los procesos activos [ID_Identificador -> ProcessInfo]
  private val activeProcesses = new ConcurrentHashMap[String, (Process, ProcessInfo)]()

  // Ruta base para volcar los logs del stdout/stderr de los scripts

  implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "MariposaScraper")
  implicit val ec: ExecutionContext = ExecutionContext.fromExecutor(Executors.newFixedThreadPool(4))

  implicit val statusFormat: RootJsonFormat[StatusResponse] = jsonFormat5(StatusResponse)

  def main(args: Array[String]): Unit = {
    // Asegurar que el directorio de logs exista en el nodo

    val routes = pathPrefix("v1" / "scraper") {
      // 1) RUN PROCESS: /v1/scraper/start/mi-scraper
      // IMPORTANT! in your bash use "exec" to keep the PID! E.g. "exec java -jar myprogram.jar"
      path("start" / Segment) { scraperId =>
        post {
          if (activeProcesses.containsKey(scraperId)) {
            complete(StatusCodes.BadRequest, Map("error" -> s"El scraper '$scraperId' ya se esta ejecutando."))
          } else {
            val home = sys.props("user.home")
            val logPath = s"$home/logs/$scraperId.log"
            val logDir = new File(s"$home/logs")
            if (!logDir.exists())
              logDir.mkdir()
            logger.info(s"Starting: $home/apps/$scraperId")

            // Arrancar el proceso en un hilo secundario
            Future {
              val builder = new ProcessBuilder(s"./$scraperId")
              builder.directory(new File(s"$home/apps"))
              builder.redirectErrorStream()              // TODO: Spark logs are empty; call .inheritIO?
              builder.redirectOutput(new File(logPath))  // TODO: I don't see stderr

              val process = builder.start()
              val info = ProcessInfo(process.pid(), scraperId, logPath, System.currentTimeMillis())
              activeProcesses.put(scraperId, (process, info))
              logger.info(s"Process started: $info")

              val exitCode = process.waitFor()
              logger.info(s"$scraperId completed with: $exitCode")
              activeProcesses.remove(scraperId)
            }.recover{ case e => logger.error(s"ERROR: ${e.getMessage}", e) }

            complete(StatusCodes.Accepted, Map("message" -> s"Scraper '$scraperId' iniciado."))
          }
        }
      } ~
        // 2) CHECK STATUS: /v1/scraper/status/mi-scraper
        path("status" / Segment) { scraperId =>
          get {
            Option(activeProcesses.get(scraperId)) match {
              case Some((_, info)) =>
                val uptime = (System.currentTimeMillis() - info.startTime) / 1000
                complete(StatusResponse(info.pid, "RUNNING", info.scriptPath, info.logFile, uptime))
              case None =>
                complete(StatusCodes.OK, Map("status" -> "STOPPED", "message" -> "No hay procesos activos bajo este ID."))
            }
          }
        } ~
        // 3) RETURN LOGS: /v1/scraper/logs/mi-scraper
        path("logs" / Segment) { scraperId =>
          get {
            val logFilePath = s"logs/$scraperId.log"
            val logFile = new File(logFilePath)

            if (!logFile.exists()) {
              complete(StatusCodes.NotFound, Map("error" -> s"No se encontraron logs para '$scraperId'"))
            } else {
              // Leer de forma segura las últimas 200 líneas del log para no saturar el HTTP
              val source = scala.io.Source.fromFile(logFilePath, "UTF-8")
              try {
                val lines = source.getLines().toList.takeRight(200).mkString("\n")
                complete(lines)
              } finally {
                source.close()
              }
            }
          }
        } ~
        // 4) KILL GRACEFUL (SIGTERM): /v1/scraper/stop/mi-scraper
        path("stop" / Segment) { scraperId =>
          post {
            Option(activeProcesses.get(scraperId)) match {
              case Some((process, info)) =>
                logger.info(s"Deteniendo de forma limpia (SIGTERM) el scraper '$scraperId' con PID: ${info.pid}")

                // Enviamos señal de terminación limpia nativa de Java
                process.destroy()
                activeProcesses.remove(scraperId)

                complete(StatusCodes.OK, Map("message" -> s"Se envio señal de parada limpia (SIGTERM) al scraper '$scraperId'."))
              case None =>
                complete(StatusCodes.NotFound, Map("error" -> s"No se encontro un proceso activo para '$scraperId'"))
            }
          }
        }
    }

    // Encender el servidor HTTP en el puerto indicado
    val server = Http().newServerAt("0.0.0.0", serverPort).bind(routes)
    server.onComplete {
      case Success(binding) => logger.info(s"🚀 Mariposa Scraper Orchestrator ONLINE en puerto ${binding.localAddress.getPort}")
      case Failure(e)       => logger.error("Fallo al iniciar el servidor de control", e); system.terminate()
    }

    sys.addShutdownHook {
      logger.info("Apagando orquestador. Matando scrapers residuales...")
      activeProcesses.values().forEach { case (p, _) => p.destroy() }
      Try(Await.result(server.flatMap(_.unbind()), 2.seconds))
      system.terminate()
    }
  }
}
