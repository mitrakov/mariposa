package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.Trigger
import org.slf4j.LoggerFactory

case class Kafka2Hive private (
   private val hiveTable: String = "myTable",
   private val kafkaTopic: String = "myTopic",
   private val kafkaBootstrapServers: String = "localhost:9092",
   private val pollInterval: String = "5 seconds",
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHiveTable(table: String): Kafka2Hive = copy(hiveTable = table)
  def withKafkaTopic(topic: String): Kafka2Hive = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): Kafka2Hive = copy(kafkaBootstrapServers = servers)
  def withPollInterval(interval: String): Kafka2Hive = copy(pollInterval = interval)

  def build(): Runnable = () => {
    logger.info("=== Mariposa::Kafka2Hive ===")
    printParameters()
    // TODO: check kafka topic and hive table here

    val spark = SparkSession.builder()
      .appName("KafkaToHive-Mariposa")
      .config("spark.sql.streaming.kafka.enableMinMaxLatency", "false") // fix NPE: metrics(KafkaMicroBatchStream.scala:520)
      .config("spark.sql.warehouse.dir", "/user/hive/warehouse")
      .config("hive.metastore.uris", "thrift://localhost:9083")
      .enableHiveSupport()
      .getOrCreate()

    val jsonSchema = new StructType()
      .add("rowkey", StringType)
      .add("metric", StringType)
      .add("value", StringType)

    val kafkaDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBootstrapServers)
      .option("subscribe", kafkaTopic)
      .option("startingOffsets", "earliest")
      .option("failOnDataLoss", "false") // for stability
      .load()

    val processedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as json_payload")
      .select(from_json(col("json_payload"), jsonSchema).as("data"))
      .select("data.*")
      .filter("rowkey IS NOT NULL")

    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        if (!batchDF.isEmpty) {
          println(s"--- Committing Batch $batchId to Hive ---")
          batchDF.write.insertInto(hiveTable)
        }
      }
      .trigger(Trigger.ProcessingTime(pollInterval))
      .option("checkpointLocation", "/tmp/spark-checkpoints/mariposa-hive")
      .start()

    query.awaitTermination()
  }

  private def printParameters(): Unit = {
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      logger.info("{}: {}", k, v)
    }
  }
}

object Kafka2Hive {
  def builder() = new Kafka2Hive()
}

/*
  spark-shell: spark.sql("""CREATE TABLE telemetry_hive (rowkey STRING, metric STRING, value STRING) USING HIVE;""")
  kafka-topics.sh --bootstrap-server localhost:9092 --create --topic telemetry
  spark-submit --class com.mitrakoff.mariposa.Kafka2Hive mariposa-framework-assembly-1.0.0.jar
  kafka-console-producer.sh --bootstrap-server localhost:9092 --topic telemetry
  {"rowkey": "sensor_002", "metric": "temperature", "value": "25.6"}
  spark-shell: spark.sql("SELECT * FROM telemetry_hive;").show(truncate = false)
*/
