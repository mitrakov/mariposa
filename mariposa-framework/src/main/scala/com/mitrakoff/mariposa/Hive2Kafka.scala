package com.mitrakoff.mariposa

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.{col, struct, to_json}
import org.slf4j.LoggerFactory


case class Hive2Kafka  private (
    private val hiveTable: String = "myTable",
    private val kafkaTopic: String = "myTopic",
    private val kafkaBootstrapServers: String = "localhost:9092",
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHiveTable(table: String): Hive2Kafka = copy(hiveTable = table)
  def withKafkaTopic(topic: String): Hive2Kafka  = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): Hive2Kafka  = copy(kafkaBootstrapServers = servers)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Hive2Kafka ===")

    val spark = SparkSession.builder()
      .appName("Mariposa-Hive2Kafka")
      .enableHiveSupport()
      .getOrCreate()

    val hiveDF = spark.table(hiveTable)



    logger.info(s"Reading from Hive table: $hiveTable and publishing to Kafka: $kafkaTopic")

    // Transform to a JSON and send to Kafka
    val toKafkaDF = hiveDF.select(to_json(struct(hiveDF.columns.map(col): _*)).as("value"))
    toKafkaDF.write
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBootstrapServers)
      .option("topic", kafkaTopic)
      .save()

    logger.info("Hive  to Kafka completed successfully.")
    spark.stop()
  }
}

object Hive2Kafka {
  def builder() = new Hive2Kafka()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hiveTable      = sys.props.getOrElse("app.hive.table", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", "localhost:9092")

    builder()
      .withHiveTable(hiveTable)
      .withKafkaTopic(kafkaTopic)
      .withKafkaBootstrapServers(kafkaBootstrap)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("These properties are necessary: -Dapp.hive.table=myTable -Dapp.kafka.topic=my-topic")
}
