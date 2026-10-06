package com.mariposa

import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import com.mariposa.routes.TableRoutes
import com.mariposa.services.HBaseService
import scala.concurrent.ExecutionContextExecutor
import scala.util.{Failure, Success}

object Main {
  def main(args: Array[String]): Unit = {
    // Sistema de actores básico para Pekko Streams y HTTP
    implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "mariposa-df-viewer-backend")
    implicit val executionContext: ExecutionContextExecutor = system.executionContext

    println("🦋 Inicializando conectores del ecosistema Hadoop...")
    val hbaseService = new HBaseService()
    val tableRoutes  = new TableRoutes(hbaseService)

    // Configuración de red: Escucha global en el puerto de red clásico 8080
    val host = "0.0.0.0"
    val port = 8080

    val bindingFuture = Http().newServerAt(host, port).bind(tableRoutes.routes)

    bindingFuture.onComplete {
      case Success(binding) =>
        val localAddress = binding.localAddress
        println(s"🚀 Servidor de Mariposa activo en http://${localAddress.getHostName}:${localAddress.getPort}/")
        println(s"Apuntala tu iPhone o Mac a http://<IP_DE_TU_MAC>:$port/api/table/<TU_TABLA>")
      case Failure(ex) =>
        println(s"💥 No se pudo levantar el servidor Pekko HTTP, bro: ${ex.getMessage}")
        system.terminate()
    }
  }
}
