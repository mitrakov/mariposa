package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.slf4j.LoggerFactory

object Mariposa extends App {
  private val logger = LoggerFactory.getLogger(getClass)

  val kafka2HBase = Kafka2HBase
  val kafka2Hive = Kafka2Hive

  if (args.isEmpty) {
    logger.error("Usage: spark-submit mariposa.jar <SQL-File>")
    System.exit(1)
  }

  val src = scala.io.Source.fromFile(args.head, "UTF-8")
  val sql = src.getLines().mkString
  src.close()

  logger.info("SQL: {}", sql)
  val spark = SparkSession
    .builder()
    .enableHiveSupport()
    .getOrCreate()

  val df: DataFrame = spark.sql(sql)
  df.show(truncate = false)

  spark.close()
}
