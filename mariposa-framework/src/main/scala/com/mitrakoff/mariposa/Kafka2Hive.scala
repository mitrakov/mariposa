package com.mitrakoff.mariposa

import org.apache.spark.sql.functions.{col, from_json}
import org.apache.spark.sql.streaming.Trigger
import org.apache.spark.sql.types.{StructField, StructType}
import org.apache.spark.sql.{DataFrame, SaveMode, SparkSession}

import org.slf4j.LoggerFactory
import java.net.InetAddress

case class Kafka2Hive  private (
    private val hiveTable: String = "myTable",
    private val kafkaTopic: String = "myTopic",
    private val kafkaBootstrapServers: String = "localhost:9092",
    private val pollInterval: String = "5 seconds",
    private val infinite: Boolean = false,
    private val truststorePassword: String = "",
) {
  private val logger = LoggerFactory.getLogger(getClass)

  def withHiveTable(table: String): Kafka2Hive = copy(hiveTable = table)
  def withKafkaTopic(topic: String): Kafka2Hive  = copy(kafkaTopic = topic)
  def withKafkaBootstrapServers(servers: String): Kafka2Hive  = copy(kafkaBootstrapServers = servers)
  def withPollInterval(interval: String): Kafka2Hive  = copy(pollInterval = interval)
  def withRunInfinitely(infinite: Boolean): Kafka2Hive  = copy(infinite = infinite)
  def withTruststorePass(password: String): Kafka2Hive = copy(truststorePassword = password)

  def build(): Runnable = () => {
    logger.info("=== Mariposa-Kafka2Hive ===")
    printParameters()
    // TODO: check kafka topic and hive table here

    val spark = SparkSession.builder()
      .appName(s"Mariposa-Kafka2Hive-$kafkaTopic")
      .config("spark.sql.warehouse.dir", "/user/hive/warehouse")
      .config("hive.metastore.uris", "thrift://node49.host:9083")       // TODO: hardcode
      .enableHiveSupport()
      .getOrCreate()

    // get schema from Hive table
    val hiveSchema = getHiveTableSchema(spark, hiveTable)
    logger.info(s"Hive table schema: ${hiveSchema.treeString}")

    // configuration for secured Kafka
    val kafkaOptions = Map(
      "kafka.bootstrap.servers"  -> kafkaBootstrapServers,
      "subscribe"                -> kafkaTopic,
      "startingOffsets"          -> "earliest",
      "failOnDataLoss"           -> "false", // fix: "Some data may have been lost because they are not available in Kafka any more"
      "kafka.security.protocol"  -> "SASL_SSL",
      "kafka.sasl.kerberos.service.name" -> "kafka",
      "kafka.ssl.truststore.location" -> "/opt/vault/certs/truststore.jks",
      "kafka.ssl.truststore.password" -> truststorePassword,
    )

    val kafkaDF = spark.readStream.format("kafka").options(kafkaOptions).load()

    // parse JSON using Hive schema
    // TODO: lowercase json keys for f*cking Hive
    val processedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as json_payload")
      .select(from_json(col("json_payload"), hiveSchema).as("data"))
      .select("data.*")
      //.filter("rowkey IS NOT NULL") TODO: rowkey hardcoded

    // processing every batch
    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        val count = batchDF.count()
        if (count > 0) {
          logger.info(s"--- Writing Batch $batchId ($count rows) to Hive ($hiveTable) ---")
          batchDF.show()

          // match column order to Hive table
          val orderedDF = batchDF.select(hiveSchema.fieldNames.map(col): _*)
          orderedDF.write.mode(SaveMode.Append).insertInto(hiveTable)
        } else logger.info(s"--- Batch $batchId is empty, skipping ---")
      }
      .trigger(if (infinite) Trigger.ProcessingTime(pollInterval) else Trigger.AvailableNow())
      .option("checkpointLocation", s"/tmp/spark-checkpoints/mariposa-hive-$kafkaTopic") // TODO: /tmp/?
      .start()

    query.awaitTermination()
    logger.info("Kafka to Hive  completed successfully.")
    spark.close()
  }

  /**
   * Get Hive table schema as a Spark StructType
   */
  private def getHiveTableSchema(spark: SparkSession, table: String): StructType = {
    val tableDF = spark.table(table).limit(0) // empty DataFrame with schema
    StructType(tableDF.schema.map { field =>
      // convert nullable to true to handle missing JSON fields
      StructField(field.name, field.dataType, nullable = true)
    })
  }

  private def printParameters(): Unit = {
    logger.info("Builder parameters are:")
    (productElementNames zip productIterator).toList.sortBy(_._1).foreach { case (k, v) =>
      val value = if (k.toLowerCase.contains("password") || k.toLowerCase.contains("secret")) "*" * v.toString.length else v
      logger.info("{}: {}", k, value)
    }
  }
}

object Kafka2Hive {
  def builder() = new Kafka2Hive()

  def main(args: Array[String]): Unit = {
    System.setProperty("spark.sql.streaming.kafka.enableMinMaxLatency", "false") // Fix NPE error on Kafka-Metrics
    Mariposa.printProps()

    val hiveTable      = sys.props.getOrElse("app.hive.table", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", s"${InetAddress.getLocalHost.getHostName}:9092")
    val pollInterval   = sys.props.getOrElse("app.kafka.poll.interval", "5 seconds")
    val truststorePass = sys.props.getOrElse("app.security.truststore.password", "")
    val kafkaInfinite  = sys.props.get("app.kafka.run.infinitely").flatMap(_.toBooleanOption).getOrElse(false)

    builder()
      .withHiveTable(hiveTable)
      .withKafkaTopic(kafkaTopic)
      .withKafkaBootstrapServers(kafkaBootstrap)
      .withPollInterval(pollInterval)
      .withRunInfinitely(kafkaInfinite)
      .withTruststorePass(truststorePass)
      .build()
      .run()
  }

  private def throwErr: Nothing =
    throw new Exception("Required properties: -Dapp.hive.table=myTable -Dapp.kafka.topic=my-topic")
}

/*
spark-shell: spark.sql("CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;")
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic test-topic-1

export JKS_PASSWORD=555
spark-submit \
  --driver-java-options=" \
   -Dapp.hive.table=test_table \
   -Dapp.kafka.topic=test-topic-1 \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  mariposa-assembly-1.0.0.jar

kafka-console-producer.sh --bootstrap-server $(hostname):9092 --topic test-topic-1 --command-config $KAFKA_HOME/config/sasl.properties
  {"rowkey": "sensor_002", "metric": "temperature", "value": "25.6"}
spark-shell: spark.sql("SELECT * FROM test_table;").show(truncate = false)
*/
