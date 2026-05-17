package com.mitrakoff.mariposa

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.{col, struct, to_json}

import org.slf4j.LoggerFactory
import java.net.InetAddress

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
    printParameters()

    val spark = SparkSession.builder()
      .appName("Mariposa-Hive2Kafka")
      .enableHiveSupport()
      .getOrCreate()
    // TODO! Check table and kafka topic!

    val hiveDF = spark.table(hiveTable)



    logger.info(s"Reading from Hive table: $hiveTable and publishing to Kafka: $kafkaTopic")

    // configuration for secured Kafka
    val kafkaOptions = Map(
      "kafka.bootstrap.servers"  -> kafkaBootstrapServers,
      "topic"                    -> kafkaTopic,
      "kafka.security.protocol"  -> "SASL_SSL",
      "kafka.sasl.kerberos.service.name" -> "kafka",
      "kafka.ssl.truststore.location" -> "/opt/hadoop/etc/hadoop/certs/truststore.jks",
      "kafka.ssl.truststore.password" -> "marip0sa_jKs",
    )

    // Transform to a JSON and send to Kafka
    val toKafkaDF = hiveDF.select(to_json(struct(hiveDF.columns.map(col): _*)).as("value"))
    toKafkaDF.write.format("kafka").options(kafkaOptions).save()

    logger.info("Hive  to Kafka completed successfully.")
    spark.stop()
  }

  private def printParameters(): Unit = {
    logger.info("Builder parameters are:")
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      logger.info("{}: {}", k, v)
    }
  }
}

object Hive2Kafka {
  def builder() = new Hive2Kafka()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hiveTable      = sys.props.getOrElse("app.hive.table", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", s"${InetAddress.getLocalHost.getHostName}:9092")

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

/*
spark-shell:
  spark.sql("CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;")
  spark.sql("""INSERT INTO test_table VALUES ("k1", "sensor1", "44.4")""")

kafka-console-consumer.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties \
  --topic test-topic-1 --from-beginning

spark-submit \
  --driver-java-options="-Dapp.hive.table=test_table -Dapp.kafka.topic=test-topic-1 \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Hive2Kafka \
  mariposa-assembly-1.0.0.jar
 */
