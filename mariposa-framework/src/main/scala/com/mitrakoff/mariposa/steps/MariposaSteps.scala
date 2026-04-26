package com.mitrakoff.mariposa.steps

import com.mitrakoff.mariposa.Mariposa
import io.cucumber.datatable.DataTable
import io.cucumber.scala.{EN, ScalaDsl}
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerRecord}
import org.apache.kafka.clients.consumer.KafkaConsumer

import java.util.{Collections, Properties}
import java.time.Duration
import scala.jdk.CollectionConverters._

class MariposaSteps extends ScalaDsl with EN {
  private val strSerializer   = "org.apache.kafka.common.serialization.StringSerializer"
  private val strDeserializer = "org.apache.kafka.common.serialization.StringDeserializer"
  private val kafkaProps = new Properties()
  kafkaProps.put("bootstrap.servers", "localhost:9092")
  kafkaProps.put("key.serializer", strSerializer)
  kafkaProps.put("value.serializer", strSerializer)
  kafkaProps.put("key.deserializer", strDeserializer)
  kafkaProps.put("value.deserializer", strDeserializer)
  kafkaProps.put("group.id", "mariposa-test-group")
  kafkaProps.put("auto.offset.reset", "earliest")

  Given("""a message is sent to Kafka topic {string}:""") { (topic: String, dataTable: DataTable) =>
    val producer = new KafkaProducer[String, String](kafkaProps)
    val row = dataTable.asMaps().get(0)
    // Convertimos el row a JSON (puedes usar Jackson o similar, aquí lo hacemos manual para el ejemplo)
    val json = s"""{"rowkey":"${row.get("rowkey")}","metric":"${row.get("metric")}","value":"${row.get("value")}"}"""

    producer.send(new ProducerRecord(topic, row.get("rowkey"), json)).get()
    println(s"Sent message to topic $topic with key: ${row.get("rowkey")}:\n$json")
    Thread.sleep(2000L)
    producer.flush()
    producer.close()
  }

  When("""a Mariposa command is executed:""") { (sql: String) =>
    Mariposa.runMariposaSql(sql)
  }

  Then("""the Kafka topic {string} should contain a message with rowkey {string}""") { (topic: String, expectedRowkey: String) =>
    val consumer = new KafkaConsumer[String, String](kafkaProps)
    consumer.subscribe(Collections.singletonList(topic))

    // Polling hasta encontrar el mensaje o timeout
    var found = false
    val startTime = System.currentTimeMillis()
    while (!found && (System.currentTimeMillis() - startTime) < 20000) { // 20s timeout
      val records = consumer.poll(Duration.ofSeconds(1))
      records.asScala.foreach { record =>
        println(s"record = $record")
        if (record.value().contains(expectedRowkey)) found = true
      }
    }
    consumer.close()
    assert(found, s"No se encontró el mensaje con rowkey $expectedRowkey en el topic $topic")
  }
}
