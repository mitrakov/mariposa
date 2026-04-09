package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.Trigger
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.slf4j.LoggerFactory

case class Kafka2HBase private (
    private val hbaseCatalog: String = "{}",
    private val kafkaTopic: String = "myTopic",
    private val kafkaBootstrapServers: String = "localhost:9092",
    private val pollInterval: String = "5 seconds",
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseJsonCatalog(catalog: String): Kafka2HBase = copy(hbaseCatalog = catalog)
  def withKafkaTopic(topic: String): Kafka2HBase = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): Kafka2HBase = copy(kafkaBootstrapServers = servers)
  def withPollInterval(interval: String): Kafka2HBase = copy(pollInterval = interval)

  def build(): Runnable = () => {
    logger.info("=== Mariposa::Kafka2HBase ===")
    printParameters()
    // TODO: check kafka topic and hbase table here

    val spark = SparkSession.builder()
      .appName("KafkaToHBase-Mariposa")
      .config("spark.sql.streaming.kafka.enableMinMaxLatency", "false") // fix NPE: KafkaMicroBatchStream$.metrics(....scala:520)
      .getOrCreate()

    // define the JSON schema coming from Kafka
    val jsonSchema = new StructType()
      .add("rowkey", StringType)
      .add("metric", StringType)
      .add("value", StringType)

    // read from Kafka
    val kafkaDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBootstrapServers)
      .option("subscribe", kafkaTopic)
      .option("startingOffsets", "latest")
      .option("failOnDataLoss", "false") // fix error "Some data may have been lost because they are not available in Kafka any more"
      .load()

    // parse JSON and filter out empty rowkeys
    val processedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as json_payload")
      .select(from_json(col("json_payload"), jsonSchema).as("data"))
      .select("data.*")
      .filter("rowkey IS NOT NULL AND rowkey != ''")

    // 2rite to HBase with a 5-second trigger
    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        if (!batchDF.isEmpty) {
          println(s"--- Writing Batch $batchId to HBase ---")
          batchDF.show()

          batchDF.write
            .options(Map(HBaseTableCatalog.tableCatalog -> hbaseCatalog))
            .format("org.apache.hadoop.hbase.spark")
            .save()
        }
      }
      .trigger(Trigger.ProcessingTime(pollInterval))
      .option("checkpointLocation", "/tmp/spark-checkpoints/mariposa")
      .start()

    query.awaitTermination()
  }

  private def printParameters(): Unit = {
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      logger.info("{}: {}", k, v)
    }
  }
}

object Kafka2HBase {
  def builder() = new Kafka2HBase()
}

/*
  hbase shell: create 'sensor_data', 'cf1';
  kafka-topics.sh --bootstrap-server localhost:9092 --create --topic telemetry
  spark-submit --class com.mitrakoff.mariposa.Kafka2HBase mariposa-framework-assembly-1.0.0.jar
  kafka-console-producer.sh --bootstrap-server localhost:9092 --topic telemetry
  {"rowkey": "sensor_001", "metric": "temperature", "value": "24.5"}
  hbase shell: scan 'sensor_data';
*/
