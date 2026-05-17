package com.mitrakoff.mariposa

import io.cucumber.core.cli.Main
import io.cucumber.datatable.DataTable
import io.cucumber.scala.{EN, ScalaDsl}
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerRecord}
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.common.serialization.{StringDeserializer, StringSerializer}
import java.net.InetAddress
import java.util.{Collections, Properties}
import java.time.Duration
import scala.jdk.CollectionConverters.{IterableHasAsScala, MapHasAsJava}

/*
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic test-topic-1
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic test-topic-2
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic test-topic-3
hbase shell: create 'sensor_data', 'cf1';
spark-shell: spark.sql("CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;")
test_catalog.json:
{
  "table":{"namespace":"default", "name":"sensor_data"},
  "rowkey":"key",
  "columns":{
    "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
    "metric":{"cf":"cf1", "col":"metric", "type":"string"},
    "value": {"cf":"cf1", "col":"value",  "type":"string"}
  }
}

spark-submit \
  --driver-java-options="-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Test mariposa-assembly-1.0.0.jar
*/
// TODO: For some reason, first attempt always fail; all subsequent attempts are OK. Check why.
object Test extends App {
  Main.run("classpath:features", "--glue", "com.mitrakoff.mariposa")
}

class Test extends ScalaDsl with EN {
  private val kafkaProps = new Properties()
  kafkaProps.putAll(Map(
    "bootstrap.servers"  -> s"${InetAddress.getLocalHost.getHostName}:9092",
    "key.serializer"     -> classOf[StringSerializer].getName,
    "value.serializer"   -> classOf[StringSerializer].getName,
    "key.deserializer"   -> classOf[StringDeserializer].getName,
    "value.deserializer" -> classOf[StringDeserializer].getName,
    "group.id" -> "mariposa-test-group", // fix InvalidGroupIdException: To use the group management or offset commit APIs...
    "security.protocol" -> "SASL_SSL",
    "sasl.kerberos.service.name" -> "kafka",
    "ssl.truststore.location" -> "/opt/hadoop/etc/hadoop/certs/truststore.jks",
    "ssl.truststore.password" -> "marip0sa_jKs",
  ).asJava)

  Given("""a message is sent to Kafka topic {string}:""") { (topic: String, dataTable: DataTable) =>
    val producer = new KafkaProducer[String, String](kafkaProps)
    val row = dataTable.asMaps().get(0)
    val json = s"""{"rowkey":"${row.get("rowkey")}","metric":"${row.get("metric")}","value":"${row.get("value")}"}"""

    producer.send(new ProducerRecord(topic, row.get("rowkey"), json)).get()
    println(s"Sent message to topic $topic with key: ${row.get("rowkey")}:\n$json\n")
    producer.flush()
    producer.close()
  }

  When("""a Mariposa command is executed:""") { (sql: String) =>
    Mariposa.runMariposaSql(sql)
  }

  Then("""the Kafka topic {string} should contain a message with rowkey {string}""") { (topic: String, expectedRowkey: String) =>
    val consumer = new KafkaConsumer[String, String](kafkaProps)
    consumer.subscribe(Collections.singletonList(topic))

    // poll until the message found, or timeout happens
    var found = false
    val startTime = System.currentTimeMillis()
    while (!found && (System.currentTimeMillis() - startTime) < 20000) { // 20s timeout
      val records = consumer.poll(Duration.ofSeconds(1))
      records.asScala.foreach { record =>
        println(s"Kafka Record: $record")
        if (record.value().contains(expectedRowkey))
          found = true
      }
    }
    consumer.close()
    assert(found, s"No found messages with key $expectedRowkey in the topic $topic")
  }
}

/*
TODO:
WARN  [ReadOnlyZKClient-namenode.host:2181,datanode1.host:2181,datanode2.host:2181@0x7b5d3ac5-SendThread(namenode.host:2181)] zookeeper.ClientCnxn: SASL configuration failed. Will continue connection to Zookeeper server without SASL authentication, if Zookeeper server allows it.
javax.security.auth.login.LoginException: No JAAS configuration section named 'Client' was found in specified JAAS configuration file: '/opt/kafka/config/kafka_jaas.conf'.
	at org.apache.zookeeper.client.ZooKeeperSaslClient.<init>(ZooKeeperSaslClient.java:192) ~[zookeeper-3.9.4.jar:3.9.4]
	at org.apache.zookeeper.ClientCnxn$SendThread.startConnect(ClientCnxn.java:1150) [zookeeper-3.9.4.jar:3.9.4]
	at org.apache.zookeeper.ClientCnxn$SendThread.run(ClientCnxn.java:1200) [zookeeper-3.9.4.jar:3.9.4]

2026-05-17T08:30:50,904 INFO  [stream execution thread for [id = 53a9e873-7d1d-4727-b548-56e1ca1c7767, runId = a65f1e14-faec-41b9-b5d8-7d23bacd3f09]] admin.AdminClientConfig: These configurations '[key.deserializer, value.deserializer, enable.auto.commit, max.poll.records, auto.offset.reset]' were supplied but are not used yet.
2026-05-17T08:30:50,905 INFO  [stream execution thread for [id = 53a9e873-7d1d-4727-b548-56e1ca1c7767, runId = a65f1e14-faec-41b9-b5d8-7d23bacd3f09]] utils.AppInfoParser: Kafka version: 3.9.1
2026-05-17T08:30:50,905 INFO  [stream execution thread for [id = 53a9e873-7d1d-4727-b548-56e1ca1c7767, runId = a65f1e14-faec-41b9-b5d8-7d23bacd3f09]] utils.AppInfoParser: Kafka commitId: f745dfdcee2b9851
*/
