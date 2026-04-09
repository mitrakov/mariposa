package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.slf4j.LoggerFactory

object Mariposa extends App {
  private lazy val logger = LoggerFactory.getLogger(getClass) // must be lazy to avoid NPE when run with "--class..."

  // these values must be "def" to avoid possible NPE
  def kafka2HBase = Kafka2HBase // TODO: lazy val? check on external Sbt/Maven project
  def kafka2Hive = Kafka2Hive    // TODO: lazy val? check on external Sbt/Maven project

  if (args.isEmpty) {
    val usage = """Usage:
      |spark-submit mariposa.jar <SQL-File>
      |or:
      |spark-submit --class com.mitrakoff.mariposa.SomeClass --driver-java-options="-Dapp.kafka.topic=mytopic..." mariposa.jar
      |
      |Available programs are:
      |com.mitrakoff.mariposa.Kafka2Hive
      |com.mitrakoff.mariposa.Kafka2HBase
      |""".stripMargin
    System.err.println(usage)
    System.exit(1)
  }

  runSqlFile()

  def printProps(): Unit = {
    if (sys.props exists (_._1.startsWith("app.")))
      logger.info("App properties are:")
    sys.props collect { case (k, v) if k.startsWith("app.") =>
      logger.info("{}: {}", k, v)
    }
  }

  def readFileLocal(path: String): String = {
    val src = scala.io.Source.fromFile(path, "UTF-8")
    val result = src.getLines().mkString
    src.close()
    result
  }

  private def runSqlFile(): Unit = {
    val sql = readFileLocal(args.head)
    logger.info("SQL: {}", sql)

    val spark = SparkSession
      .builder()
      .enableHiveSupport()
      .getOrCreate()

    val df: DataFrame = spark.sql(sql)
    df.show(truncate = false)

    spark.close()
  }
}
