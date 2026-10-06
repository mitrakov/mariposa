package com.mariposa.services

import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.TableName
import org.apache.hadoop.hbase.client.{Connection, ConnectionFactory, Scan}
import org.apache.hadoop.hbase.util.Bytes
import scala.jdk.CollectionConverters._

case class HBaseDataPage(columns: List[String], rows: List[List[Option[String]]], nextRowKey: Option[String])

class HBaseService {
  // Inicializa la configuración por defecto de HBase (busca hbase-site.xml en el classpath)
  private val config = HBaseConfiguration.create()
  private val connection: Connection = ConnectionFactory.createConnection(config)

  def fetchTablePage(tableNameStr: String, startRow: Option[String], limit: Int): HBaseDataPage = {
    val table = connection.getTable(TableName.valueOf(tableNameStr))
    val scan = new Scan()
    scan.setCaching(limit)
    scan.setLimit(limit + 1) // Pedimos uno más para verificar si hay una siguiente página

    // Si Flutter nos envía el rowKey de corte, arrancamos el escaneo desde ahí
    startRow.foreach(row => scan.withStartRow(Bytes.toBytes(row)))

    val scanner = table.getScanner(scan)
    val results = scanner.asScala.toList
    scanner.close()
    table.close()

    // 1. Extraer de manera dinámica todos los nombres de columnas presentes en este bloque
    val detectedColumns = results.flatMap { result =>
      result.listCells().asScala.map { cell =>
        val qualifier = Bytes.toString(cell.getQualifierArray, cell.getQualifierOffset, cell.getQualifierLength)
        qualifier
      }
    }.distinct.sorted

    // Aseguramos que la columna 'id' (RowKey) encabece siempre nuestra lista de metadatos
    val columnsList = "id" :: detectedColumns

    // 2. Procesar las filas emparejándolas con las columnas detectadas (colocando None si falta la celda)
    val allRowsData = results.take(limit).map { result =>
      val rowKey = Bytes.toString(result.getRow)

      columnsList.map {
        case "id" => Some(rowKey)
        case col =>
          // Buscamos si la columna existe en alguna familia (mapeo dinámico simplificado)
          val cellOpt = result.listCells().asScala.find { cell =>
            val qual = Bytes.toString(cell.getQualifierArray, cell.getQualifierOffset, cell.getQualifierLength)
            qual == col
          }
          cellOpt.map(cell => Bytes.toString(cell.getValueArray, cell.getValueOffset, cell.getValueLength))
      }
    }

    // 3. Determinar el rowKey para la siguiente página de Flutter
    val nextRowKey = if (results.size > limit) {
      Some(Bytes.toString(results.last.getRow))
    } else {
      None
    }

    HBaseDataPage(columnsList, allRowsData, nextRowKey)
  }
}
