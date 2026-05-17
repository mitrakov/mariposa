package com.mitrakoff.mariposa

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions.{col, struct, to_json}
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog
import org.slf4j.LoggerFactory
import java.net.InetAddress

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
    printParameters()

    val spark = SparkSession.builder()
      .appName("Mariposa-HBase2Kafka")
      .getOrCreate()
    // TODO! Check table and kafka topic! Otherwise you will get stupid errors like:
    //  java.lang.NoClassDefFoundError: org/apache/hadoop/hbase/CompatibilityFactory
    /*
    val conn = ConnectionFactory.createConnection(spark.sparkContext.hadoopConfiguration)
    if (!conn.getAdmin.tableExists(TableName.valueOf("sensor_data"))) {
      logger.error("¡La tabla sensor_data no existe en HBase!")
    }
    conn.close()
    */


    val hbaseDF = spark.read
      .options(Map(HBaseTableCatalog.tableCatalog -> hbaseCatalog))
      .format("org.apache.hadoop.hbase.spark")
      .load()
    logger.info(s"Reading from HBase catalog: $hbaseCatalog and publishing to Kafka: $kafkaTopic")

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
    val toKafkaDF = hbaseDF.select(to_json(struct(hbaseDF.columns.map(col): _*)).as("value"))
    toKafkaDF.write.format("kafka").options(kafkaOptions).save()

    logger.info("HBase to Kafka completed successfully.")
    spark.stop()
  }

  private def printParameters(): Unit = {
    logger.info("Builder parameters are:")
    (productElementNames zip productIterator).toList sortBy (_._1) foreach { case (k, v) =>
      logger.info("{}: {}", k, v)
    }
  }
}

object HBase2Kafka {
  def builder() = new HBase2Kafka()

  def main(args: Array[String]): Unit = {
    Mariposa.printProps()

    val hbaseCatalog   = sys.props.getOrElse("app.hbase.json.catalog", throwErr)
    val kafkaTopic     = sys.props.getOrElse("app.kafka.topic", throwErr)
    val kafkaBootstrap = sys.props.getOrElse("app.kafka.bootstrap.servers", s"${InetAddress.getLocalHost.getHostName}:9092")

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

/*
hbase shell:
  create 'sensor_data','cf1';
  put 'sensor_data', 'sensor_001', 'cf1:metric', 'temperatura';
  put 'sensor_data', 'sensor_001', 'cf1:value', '49.1';

kafka-console-consumer.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties \
  --topic test-topic-2 --from-beginning

catalog.json:
{
  "table":{"namespace":"default", "name":"sensor_data"},
  "rowkey":"key",
  "columns":{
    "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
    "metric":{"cf":"cf1", "col":"metric", "type":"string"},
    "value":{"cf":"cf1", "col":"value", "type":"string"}
  }
}



spark-submit \
  --driver-java-options="-Dapp.hbase.json.catalog=catalog.json -Dapp.kafka.topic=test-topic-2 \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.HBase2Kafka \
  mariposa-assembly-1.0.0.jar
*/
