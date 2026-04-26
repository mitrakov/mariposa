package com.mitrakoff.mariposa

import org.antlr.v4.runtime.{CharStreams, CommonTokenStream}
import org.slf4j.LoggerFactory

object Mariposa extends App {
  // the following values must be "lazy" to avoid possible NPE
  private lazy val logger = LoggerFactory.getLogger(getClass)
  lazy val kafka2HBase = Kafka2HBase
  lazy val kafka2Hive = Kafka2Hive
  lazy val hive2Kafka = Hive2Kafka
  lazy val hbase2Kafka = HBase2Kafka

  if (args.isEmpty) {
    System.err.println("""Usage:
      |spark-submit mariposa.jar file.sql
      |or:
      |spark-submit --class com.mitrakoff.mariposa.SomeClass --driver-java-options="-Dapp.kafka.topic=mytopic ..." mariposa.jar
      |
      |Available programs are:
      |com.mitrakoff.mariposa.Kafka2Hive
      |com.mitrakoff.mariposa.Kafka2HBase
      |com.mitrakoff.mariposa.Hive2Kafka
      |com.mitrakoff.mariposa.HBase2Kafka
      |""".stripMargin)
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

  /**
   * Reads file from a local File System
   * @param path local path
   * @return all lines as a String
   */
  def readFileLocal(path: String): String = {
    val src = scala.io.Source.fromFile(path, "UTF-8")
    val result = src.getLines().mkString(System.lineSeparator())
    src.close()
    result
    // TODO: add read from resource
  }

  private def runSqlFile(): Unit = {
    val sql = readFileLocal(args.head)
    logger.info("SQL: {}", sql)
    runMariposaSql(sql)
  }

  /**
   * Run SQL in MariposaSQL dialect
   * @param sql SQL string
   */
  def runMariposaSql(sql: String): Unit = {
    val tree = new MariposaSQLParser(new CommonTokenStream(new MariposaSQLLexer(CharStreams.fromString(sql)))).mariposaCommand()

    // DOWNLOAD FROM KAFKA
    if (tree.downloadCommand() != null) {
      val cmd = tree.downloadCommand()
      val topic = cmd.topic.getText.replace("'", "")
      val servers = cmd.servers.getText.replace("'", "")
      val options = extractOptions(cmd.optionList())

      val infinite = options.get("infinite").flatMap(_.toBooleanOption).getOrElse(false)
      val interval = options.getOrElse("pollInterval", "5 seconds")

      cmd.target.getType match {
        case MariposaSQLParser.HBASE_TABLE =>
          val catalogPath = cmd.catalog.getText.replace("'", "")
          Kafka2HBase.builder()
            .withHBaseJsonCatalog(readFileLocal(catalogPath))
            .withKafkaTopic(topic)
            .withKafkaBootstrapServers(servers)
            .withRunInfinitely(infinite)
            .withPollInterval(interval)
            .build()
            .run()

        case MariposaSQLParser.HIVE_TABLE =>
          val tableName = cmd.hiveTable.getText.replace("'", "")
          Kafka2Hive.builder()
            .withHiveTable(tableName)
            .withKafkaTopic(topic)
            .withKafkaBootstrapServers(servers)
            .withRunInfinitely(infinite)
            .withPollInterval(interval)
            .build()
            .run()
      }
    }

    // UPLOAD TO KAFKA
    else if (tree.uploadCommand() != null) {
      val cmd = tree.uploadCommand()
      val topic = cmd.topic.getText.replace("'", "")
      val servers = cmd.servers.getText.replace("'", "")
      val options = extractOptions(cmd.optionList())

      cmd.source.getType match {
        case MariposaSQLParser.HBASE_TABLE =>
          val catalogPath = cmd.catalog.getText.replace("'", "")
          HBase2Kafka.builder()
            .withHBaseJsonCatalog(readFileLocal(catalogPath))
            .withKafkaTopic(topic)
            .withKafkaBootstrapServers(servers)
            .build()
            .run()

        case MariposaSQLParser.HIVE_TABLE =>
          val tableName = cmd.hiveTable.getText.replace("'", "")
          Hive2Kafka.builder()
            .withHiveTable(tableName)
            .withKafkaTopic(topic)
            .withKafkaBootstrapServers(servers)
            .build()
            .run()
      }
    }
  }

  private def extractOptions(ctx: MariposaSQLParser.OptionListContext): Map[String, String] = {
    import scala.jdk.CollectionConverters.ListHasAsScala
    if (ctx != null) {
      ctx.option().asScala.map { opt =>
        val key = opt.key.getText
        val value = opt.value.getText.replace("'", "")
        key -> value
      }.toMap
    } else Map.empty
  }
}
