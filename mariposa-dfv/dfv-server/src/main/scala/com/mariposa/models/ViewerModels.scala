// src/main/scala/com/mariposa/models/ViewerModels.scala
package com.mariposa.models

import io.circe.{Encoder, Json}
import io.circe.generic.semiauto._

// Estructura limpia para la paginación de HBase
case class PaginationInfo(next_row_key: Option[String])

// Estructura exacta que espera el DataFrameResponse de tu Flutter
case class TableResponse(
                          tableName: String,
                          columns: List[String],
                          rows: List[List[Json]], // Usamos Json directo de Circe para soportar Strings o Nulls nativos
                          pagination: PaginationInfo
                        )

object ViewerModels {
  // ⚡ CONTROL ABSOLUTO: Compilación más rápida declarando Codecs explícitos
  implicit val paginationEncoder: Encoder[PaginationInfo] = deriveEncoder[PaginationInfo]
  implicit val tableResponseEncoder: Encoder[TableResponse] = deriveEncoder[TableResponse]
}
