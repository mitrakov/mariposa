package com.mitrakoff.mariposa

import io.cucumber.core.cli.Main
import io.cucumber.datatable.DataTable
import io.cucumber.scala.{EN, ScalaDsl}
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerRecord}
import org.apache.kafka.clients.consumer.KafkaConsumer
import java.util.{Collections, Properties}
import java.time.Duration
import scala.jdk.CollectionConverters._

// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-1
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-2
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-3
// spark.sql("""CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;""")
// spark-submit --class com.mitrakoff.mariposa.Test mariposa-assembly-1.0.0.jar
// test_catalog.json:
/*{
  "table":{"namespace":"default", "name":"sensor_data"},
  "rowkey":"key",
  "columns":{
    "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
    "metric":{"cf":"cf1", "col":"metric", "type":"string"},
    "value": {"cf":"cf1", "col":"value",  "type":"string"}
  }
}*/
object Test extends App {
  Main.run("classpath:features", "--glue", "com.mitrakoff.mariposa")
}

class Test extends ScalaDsl with EN {
  private val strSerializer   = "org.apache.kafka.common.serialization.StringSerializer"
  private val strDeserializer = "org.apache.kafka.common.serialization.StringDeserializer"
  private val kafkaProps = new Properties()
  kafkaProps.putAll(Map(
    "bootstrap.servers"  -> "localhost:9092",
    "key.serializer"     -> strSerializer,
    "value.serializer"   -> strSerializer,
    "key.deserializer"   -> strDeserializer,
    "value.deserializer" -> strDeserializer,
    "group.id" -> "mariposa-test-group", // fix InvalidGroupIdException: To use the group management or offset commit APIs
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
