package com.mitrakoff.mariposa

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.{col, struct, to_json}
import org.slf4j.LoggerFactory
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog

case class HBase2Kafka private (
    private val hbaseCatalog: String = "{}",
    private val kafkaTopic: String = "myTopic",
    private val kafkaBootstrapServers: String = "localhost:9092",
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseJsonCatalog(catalog: String): HBase2Kafka = copy(hbaseCatalog = catalog)
  def withKafkaTopic(topic: String): HBase2Kafka = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): HBase2Kafka = copy(kafkaBootstrapServers = servers)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-HBase2Kafka ===")

    val spark = SparkSession.builder()
      .appName("Mariposa-HBase2Kafka")
      .getOrCreate()


    val hbaseDF = spark.read
      .options(Map(HBaseTableCatalog.tableCatalog -> hbaseCatalog))
      .format("org.apache.hadoop.hbase.spark")
      .load()
    logger.info(s"Reading from HBase catalog: $hbaseCatalog and publishing to Kafka: $kafkaTopic")

    // Transform to a JSON and send to Kafka
    val toKafkaDF = hbaseDF.select(to_json(struct(hbaseDF.columns.map(col): _*)).as("value"))
    toKafkaDF.write
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBootstrapServers)
      .option("topic", kafkaTopic)
      .save()

    logger.info("HBase to Kafka completed successfully.")
    spark.stop()
  }
}

object HBase2Kafka {
  def builder() = new HBase2Kafka()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hbaseCatalog   = sys.props.getOrElse("app.hbase.json.catalog", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", "localhost:9092")

    builder()
      .withHBaseJsonCatalog(Mariposa.readFileLocal(hbaseCatalog))
      .withKafkaTopic(kafkaTopic)
      .withKafkaBootstrapServers(kafkaBootstrap)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("These properties are necessary: -Dapp.hbase.json.catalog=hbase.json -Dapp.kafka.topic=my-topic")
}
