package com.mitrakoff.mariposa

import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.apache.spark.sql.{SaveMode, SparkSession}
import org.slf4j.LoggerFactory

case class Hive2HBase private (
  private val hbaseTableName: String = "default:my_table",
  private val hbaseCf: String = "f",
  private val hiveSql: String = "SELECT * FROM my_table"
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseTable(table: String): Hive2HBase = copy(hbaseTableName = table)
  def withHBaseColFamily(family: String): Hive2HBase = copy(hbaseCf = family)
  def withHiveSql(sql: String): Hive2HBase = copy(hiveSql = sql)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Hive2HBase ===")
    logger.info("Make sure that first column IS NOT NULL as it will be converted to 'rowkey'!")
    logger.info("SQL: {}", hiveSql)

    val spark = SparkSession.builder()
      .appName("Mariposa-Hive2HBase")
      .enableHiveSupport()
      .getOrCreate()

    try {
      val df = spark.sql(hiveSql)
      val generatedCatalog = generateCatalog(df.schema.fieldNames, df.schema.fields.map(_.dataType.simpleString))
      logger.info("Generated HBase Catalog: {}", generatedCatalog)

      df.write
        .mode(SaveMode.Overwrite)
        .options(Map(HBaseTableCatalog.tableCatalog -> generatedCatalog))
        .format("org.apache.hadoop.hbase.spark")
        .save()

      logger.info("Hive2HBase completed for {}", hbaseTableName)
    } finally {
      spark.close()
    }
  }

  /**
   * 💡 LA MAGIA: Crea el JSON del catálogo analizando las columnas del DataFrame.
   * La primera columna siempre se mapea como RowKey.
   */
  private def generateCatalog(columns: Array[String], types: Array[String]): String = {
    if (hbaseTableName.contains("."))
      logger.warn(s"Your HBase tablename contains dot ('.'), please note it's NOT a delimiter! HBase delimiter is colon (':')")
    val Array(namespace, name) = if (hbaseTableName.contains(":")) hbaseTableName.split(":") else Array("default", hbaseTableName)
    val rowKey = columns.head // La primera columna es el RowKey por convención Mariposa

    val columnsMapping = columns.zip(types).map { case (name, typ) =>
      val cf  = if (name == rowKey) "rowkey" else hbaseCf
      s""""$name":{"cf":"$cf", "col":"$name", "type":"$typ"}"""
    }.mkString(",\n")

    s"""{
       |  "table":{"namespace":"$namespace", "name":"$name"},
       |  "rowkey":"$rowKey",
       |  "columns":{$columnsMapping}
       |}""".stripMargin
  }
}

object Hive2HBase {
  def builder() = new Hive2HBase()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hbaseTable = sys.props.getOrElse("app.hbase.table", throwErr)
    val sqlFile    = sys.props.getOrElse("app.hive.sql.file", throwErr)
    val sql = Mariposa.readFileLocal(sqlFile)

    builder()
      .withHBaseTable(hbaseTable)
      .withHiveSql(sql)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("These properties are necessary: -Dapp.hbase.table=default:my_table -Dapp.hive.sql.file=hive.sql")
}

/*
CREATE TABLE IF NOT EXISTS hivetable (id STRING, temperature STRING, sensor_type STRING) STORED AS PARQUET;
INSERT INTO fz223_import VALUES 
('sensor_001', '24.5', 'temp_metric'),
('sensor_002', '19.8', 'temp_metric'),
('sensor_003', '31.2', 'humidity_metric');

mysql.sql:   SELECT * FROM hivetable;
hbase shell: create 'sensor_data','f';

spark-submit \
  --driver-java-options="-Dapp.hbase.table=sensor_data -Dapp.hive.sql.file='mysql.sql'" \
  --class com.mitrakoff.mariposa.Hive2HBase \
  mariposa-assembly-1.0.1.jar
*/
