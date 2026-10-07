package com.mariposa

import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http
import com.mariposa.routes.TableRoutes
import com.mariposa.services.HBaseService
import java.net.InetAddress
import scala.concurrent.ExecutionContextExecutor
import scala.util.{Failure, Success}

object Main {
  def main(args: Array[String]): Unit = {
    val port = args.headOption.flatMap(_.toIntOption) getOrElse {
      Console.err.println("Specify port, bro!")
      System.exit(1); 0
    }
    
    // Sistema de actores básico para Pekko Streams y HTTP
    implicit val system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "mariposa-df-viewer-backend")
    implicit val executionContext: ExecutionContextExecutor = system.executionContext

    println("🦋 Inicializando conectores del ecosistema Hadoop...")
    val hbaseService = new HBaseService()
    val tableRoutes  = new TableRoutes(hbaseService)

    // Configuración de red: Escucha global en el puerto de red clásico 8080
    val bindingFuture = Http().newServerAt("0.0.0.0", port).bind(tableRoutes.routes)

    bindingFuture.onComplete {
      case Success(binding) =>
        val localAddress = binding.localAddress
        println(s"🚀 Servidor de Mariposa activo en http://${localAddress.getHostName}:${localAddress.getPort}/")
        println(s"Apuntala tu iPhone o Mac a http://${InetAddress.getLocalHost.getHostAddress}:$port/api/table/<TU_TABLA>")
      case Failure(ex) =>
        println(s"💥 No se pudo levantar el servidor Pekko HTTP, bro: ${ex.getMessage}")
        system.terminate()
    }
  }
}
