package com.mitrakoff.mariposa

import org.apache.spark.sql.{SaveMode, SparkSession}
import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.client.ConnectionFactory
import org.apache.hadoop.hbase.TableName
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.slf4j.LoggerFactory

case class Hive2HBase private (
                                private val hbaseCatalog: String = "{}",
                                private val hiveTable: String = "my_db.my_table",
                                private val selectExprs: List[String] = List("*")
                              ) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseJsonCatalog(catalog: String): Hive2HBase = copy(hbaseCatalog = catalog)
  def withHiveTable(table: String): Hive2HBase = copy(hiveTable = table)
  def withSelectExpressions(expressions: List[String]): Hive2HBase = copy(selectExprs = expressions)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Hive2HBase ===")
    printParameters()

    // 💡 Validación previa: Asegurar que HBase y Hive estén listos antes de levantar Spark
    validateResources()

    // 💡 Crucial: .enableHiveSupport() es obligatorio para leer el Metastore de Hive
    val spark = SparkSession.builder()
      .appName("Mariposa-Hive2HBase")
      .enableHiveSupport()
      .getOrCreate()

    try {
      logger.info(s"Reading from Hive table: $hiveTable")

      // 1. Leer la tabla de Hive como un DataFrame estándar
      val hiveDF = spark.read.table(hiveTable)

      // 2. Aplicar proyecciones o transformaciones si se especificaron (por defecto "*")
      val processedDF = hiveDF.selectExpr(selectExprs: _*)

      logger.info(s"Writing data to HBase using catalog...")
      if (logger.isDebugEnabled) {
        processedDF.show(5, truncate = false)
      }

      // 3. Escribir a HBase en modo Batch Append
      processedDF.write
        .mode(SaveMode.Append)
        .options(Map(HBaseTableCatalog.tableCatalog -> hbaseCatalog))
        .format("org.apache.hadoop.hbase.spark")
        .save()

      logger.info("Hive to HBase batch migration completed successfully.")
    } catch {
      case e: Exception =>
        logger.error("Fatal error during Hive2HBase execution", e)
        throw e
    } finally {
      spark.close()
    }
  }

  /**
   * Valida la existencia de la tabla destino en HBase antes de inicializar el contexto pesado de Spark.
   */
  private def validateResources(): Unit = {
    logger.info("Validating HBase destination table availability...")
    val hbaseConfig = HBaseConfiguration.create()

    // Al usar bloques 'using' o try-with-resources nativos de Scala (vía try/finally)
    val connection = ConnectionFactory.createConnection(hbaseConfig)
    try {
      val admin = connection.getAdmin
      val tablePattern = """"name"\s*:\s*"([^"]+)"""".r
      val tableNameStr = tablePattern.findFirstMatchIn(hbaseCatalog).map(_.group(1)).getOrElse("sensor_data")

      val tableName = TableName.valueOf(tableNameStr)
      if (!admin.tableExists(tableName)) {
        throw new NoSuchElementException(s"HBase destination table '$tableNameStr' does not exist! Please create it via hbase shell first.")
      }
      logger.info(s"HBase table '$tableNameStr' verified [OK]")
    } finally {
      connection.close()
    }
  }

  private def printParameters(): Unit = {
    logger.info("Builder parameters are:")
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      val value = if (k.toLowerCase.contains("password") || k.toLowerCase.contains("secret")) "*" * v.toString.length else v
      logger.info("{}: {}", k, value)
    }
  }
}

object Hive2HBase {
  def builder() = new Hive2HBase()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hbaseCatalog = sys.props.getOrElse("app.hbase.json.catalog", throwErr)
    val hiveTable    = sys.props.getOrElse("app.hive.table", throwErr)

    // Opcional: Permite pasar columnas específicas separadas por comas (ej: -Dapp.hive.select="rowkey,metric,value")
    val selectCols   = sys.props.get("app.hive.select")
      .map(_.split(",").map(_.trim).toList)
      .getOrElse(List("*"))

    builder()
      .withHBaseJsonCatalog(Mariposa.readFileLocal(hbaseCatalog))
      .withHiveTable(hiveTable)
      .withSelectExpressions(selectCols)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("These properties are necessary: -Dapp.hbase.json.catalog=hbase.json -Dapp.hive.table=my_db.my_table")
}

/*
CREATE TABLE IF NOT EXISTS fz223_import (id STRING,temperature STRING,sensor_type STRING) STORED AS PARQUET;
INSERT INTO fz223_import VALUES 
('sensor_001', '24.5', 'temp_metric'),
('sensor_002', '19.8', 'temp_metric'),
('sensor_003', '31.2', 'humidity_metric');

hbase shell: create 'sensor_data','cf1';

catalog.json:
{
  "table": {
    "namespace": "default", 
    "name": "sensor_data"
  },
  "rowkey": "key",
  "columns": {
    "rowkey": {"cf": "rowkey", "col": "key", "type": "string"},
    "metric": {"cf": "cf1", "col": "metric", "type": "string"},
    "value":  {"cf": "cf1", "col": "value",  "type": "string"}
  }
}

spark-submit \
  --driver-memory 1g \
  --executor-memory 1g \
  --driver-java-options="-Dapp.hbase.json.catalog=catalog.json \
                         -Dapp.hive.table=fz223_import \
                         -Dapp.hive.select='id AS rowkey, sensor_type AS metric, temperature AS value'" \
  --class com.mitrakoff.mariposa.Hive2HBase \
  mariposa-assembly-1.0.1.jar
*/
