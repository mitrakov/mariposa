package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SaveMode, SparkSession}
import org.apache.spark.sql.functions.{col, from_json}
import org.apache.spark.sql.types.{StringType, StructType}
import org.apache.spark.sql.streaming.Trigger
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.slf4j.LoggerFactory

case class Kafka2HBase private (
    private val hbaseCatalog: String = "{}",
    private val kafkaTopic: String = "myTopic",
    private val kafkaBootstrapServers: String = "localhost:9092",
    private val pollInterval: String = "5 seconds",
    private val infinite: Boolean = false,
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHBaseJsonCatalog(catalog: String): Kafka2HBase = copy(hbaseCatalog = catalog)
  def withKafkaTopic(topic: String): Kafka2HBase = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): Kafka2HBase = copy(kafkaBootstrapServers = servers)
  def withPollInterval(interval: String): Kafka2HBase = copy(pollInterval = interval)
  def withRunInfinitely(infinite: Boolean): Kafka2HBase = copy(infinite = infinite)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Kafka2HBase ===")
    printParameters()
    // TODO: check kafka topic and hbase table here

    val spark = SparkSession.builder()
      .appName("Mariposa-Kafka2HBase")
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
      .filter("rowkey IS NOT NULL")

    // processing every batch
    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        if (!batchDF.isEmpty) {
          logger.info(s"--- Writing Batch $batchId to HBase ($hbaseCatalog) ---")
          batchDF.show()
          batchDF.write
            .mode(SaveMode.Append)
            .options(Map(HBaseTableCatalog.tableCatalog -> hbaseCatalog))
            .format("org.apache.hadoop.hbase.spark")
            .save()
        }
      }
      .trigger(if (infinite) Trigger.ProcessingTime(pollInterval) else Trigger.AvailableNow())
      .option("checkpointLocation", s"/tmp/spark-checkpoints/mariposa-hbase-$kafkaTopic") // TODO: /tmp/?
      .start()

    query.awaitTermination()
    logger.info("Kafka to HBase completed successfully.")
    spark.close()
  }

  private def printParameters(): Unit = {
    logger.info("Builder parameters are:")
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      logger.info("{}: {}", k, v)
    }
  }
}

object Kafka2HBase {
  def builder() = new Kafka2HBase()

  def main(args: Array[String]): Unit = {
    System.setProperty("spark.sql.streaming.kafka.enableMinMaxLatency", "false") // Fix NPE error on Kafka-Metrics
    Mariposa.printProps()

    val hbaseCatalog   = sys.props.getOrElse("app.hbase.json.catalog", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", "localhost:9092")
    val pollInterval   = sys.props.getOrElse("app.kafka.poll.interval", "5 seconds")
    val kafkaInfinite  = sys.props.get("app.kafka.run.infinitely").flatMap(_.toBooleanOption).getOrElse(false)

    builder()
      .withHBaseJsonCatalog(Mariposa.readFileLocal(hbaseCatalog))
      .withKafkaTopic(kafkaTopic)
      .withKafkaBootstrapServers(kafkaBootstrap)
      .withPollInterval(pollInterval)
      .withRunInfinitely(kafkaInfinite)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("These properties are necessary: -Dapp.hbase.json.catalog=hbase.json -Dapp.kafka.topic=my-topic")
}

/*
  hbase shell: create 'sensor_data', 'cf1';
  kafka-topics.sh --bootstrap-server localhost:9092 --create --topic telemetry
  spark-submit --class com.mitrakoff.mariposa.Kafka2HBase mariposa-framework-assembly-1.0.0.jar
  kafka-console-producer.sh --bootstrap-server localhost:9092 --topic telemetry
  kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test-topic-1 --from-beginning
  {"rowkey": "sensor_001", "metric": "temperature", "value": "24.5"}
  hbase shell: scan 'sensor_data';
*/
