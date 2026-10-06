package com.mariposa.routes

import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.model.headers._
import org.apache.pekko.http.scaladsl.server.Directives._
import org.apache.pekko.http.scaladsl.server.Route
import com.mariposa.services.HBaseService
import com.mariposa.models.{PaginationInfo, TableResponse}
import com.mariposa.models.ViewerModels._ // 💡 Importamos los encoders semiautomáticos explícitos
import com.github.pjfanning.pekkohttpcirce.FailFastCirceSupport._
import io.circe.Json

class TableRoutes(hbaseService: HBaseService) {

  private val corsHeaders = List(
    `Access-Control-Allow-Origin`.*,
    `Access-Control-Allow-Credentials`(true),
    `Access-Control-Allow-Headers`("Authorization", "Content-Type", "X-Requested-With")
  )

  val routes: Route =
    respondWithHeaders(corsHeaders) {
      pathPrefix("api" / "table" / Segment) { tableName =>
        get {
          parameters("startRow".?, "limit".as[Int].?(50)) { (startRow, limit) =>
            try {
              val dataPage = hbaseService.fetchTablePage(tableName, startRow, limit)

              // Mapeamos los arrays crudos de HBase a la estructura limpia del Case Class
              val jsonRows = dataPage.rows.map { row =>
                row.map {
                  case Some(value) => Json.fromString(value)
                  case None        => Json.Null
                }
              }

              // Instanciamos el modelo tipado
              val responsePayload = TableResponse(
                tableName = tableName,
                columns = dataPage.columns,
                rows = jsonRows,
                pagination = PaginationInfo(dataPage.nextRowKey)
              )

              // Pekko HTTP resolverá automáticamente usando tableResponseEncoder de forma semiautomática
              complete(StatusCodes.OK, responsePayload)
            } catch {
              case ex: Exception =>
                complete(StatusCodes.InternalServerError, s"Error en el cluster, bro: ${ex.getMessage}")
            }
          }
        }
      }
    }
}
