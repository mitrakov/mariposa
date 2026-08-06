package com.mitrakoff.mariposa

import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.apache.spark.sql.{SaveMode, SparkSession}
import org.slf4j.LoggerFactory
import java.util.Base64

case class Hive2HBase private (
  private val hbaseTableName: String = "default:my_table",
  private val hbaseCf: String = "f",
  private val hbaseTruncate: Boolean = true,
  private val hiveSql: String = "SELECT * FROM my_table"
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseTable(table: String): Hive2HBase = copy(hbaseTableName = table)
  def withHBaseColFamily(family: String): Hive2HBase = copy(hbaseCf = family)
  def withHBaseTruncateTable(value: Boolean): Hive2HBase = copy(hbaseTruncate = value)
  def withHiveSql(sql: String): Hive2HBase = copy(hiveSql = sql)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Hive2HBase ===")
    if (hbaseTableName.contains("."))
      logger.error(s"Your HBase tablename contains dot ('.'), please note it's NOT a delimiter! HBase delimiter is colon (':')")
    logger.info("Make sure in your SQL first column IS NOT NULL as it will be converted to 'rowkey'")
    logger.info("SQL: {}", hiveSql)

    val spark = SparkSession.builder()
      .appName("Mariposa-Hive2HBase")
      .enableHiveSupport()
      .getOrCreate()

    try {
      if (hbaseTruncate) truncateHBaseTable(spark)    // by default, hbase-spark connector overwrite new keys and leave old keys
      val df = spark.sql(hiveSql)
      val generatedCatalog = generateCatalog(df.schema.fieldNames, df.schema.fields.map(_.dataType.simpleString))
      logger.info("Generated HBase Catalog: {}", generatedCatalog)

      df.write
        .mode(SaveMode.Overwrite)
        .options(Map(HBaseTableCatalog.tableCatalog -> generatedCatalog, HBaseTableCatalog.newTable -> "5"))
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

  private def truncateHBaseTable(spark: SparkSession): Unit = {
    import org.apache.hadoop.hbase.client.ConnectionFactory
    import org.apache.hadoop.hbase.{HBaseConfiguration, TableName}

    val connection = ConnectionFactory.createConnection(HBaseConfiguration.create(spark.sparkContext.hadoopConfiguration))
    val admin = connection.getAdmin
    try {
      val hbaseTable = TableName.valueOf(hbaseTableName)
      if (admin.tableExists(hbaseTable)) {
        logger.info("HBase Table '{}' exists. Triggering truncate...", hbaseTableName)

        admin.disableTable(hbaseTable)
        admin.truncateTable(hbaseTable, true)

        logger.info("Truncate completed successfully for '{}'.", hbaseTableName)
      } else logger.info("HBase Table '{}' does not exist yet. Skipping truncation.", hbaseTableName)
    } finally {
      admin.close()
      connection.close()
    }
  }
}

object Hive2HBase {
  def builder() = new Hive2HBase()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hbaseTable = sys.props.getOrElse("app.hbase.table", throwErr)
    val sql = sys.props.get("app.hive.sql.base64")
      .map(base64 => new String(Base64.getDecoder.decode(base64)))
      .orElse(sys.props.get("app.hive.sql.file") map Mariposa.readFileLocal)
      .getOrElse(throwErr)

    builder()
      .withHBaseTable(hbaseTable)
      .withHiveSql(sql)
      .build()
      .run()
  }

  private def throwErr: Nothing = throw new Exception(
    "These properties are necessary: -Dapp.hbase.table=default:my_table;\n-Dapp.hive.sql.file=hive.sql OR -Dapp.hive.sql.base64=...\n"
  )
}

/*
spark-submit --driver-java-options="-Dapp.hbase.table=table1 -Dapp.hive.sql.file=a.sql" \
  --class com.mitrakoff.mariposa.Hive2HBase mariposa-assembly-*.jar
*/
