import org.apache.kafka.clients.producer._
import org.apache.kafka.common.serialization.StringSerializer
import java.io.FileInputStream
import java.util.Properties

class KafkaPublisher(props: Map[String, Any], propsFile: Option[String] = None) extends AutoCloseable {
  // collect properties from file and args
  private val properties = new Properties()
  properties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092")
  properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
  properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
  propsFile foreach { file =>
    val f = new FileInputStream(file)
    try {
      properties.load(f)
    } finally { f.close() }
  }
  props foreach {case (k, v) => properties.put(k, v)}

  // create producer (should be closed at the end)
  private val producer = new KafkaProducer[String, String](properties)

  /** Publish message to Kafka topic with an [optional] key and string value */
  def publish(topic: String, keyOpt: Option[String], message: String): Unit = {
    val record = keyOpt match {
      case Some(key) => new ProducerRecord[String, String](topic, key, message)
      case None      => new ProducerRecord[String, String](topic, message)
    }
    producer.send(record, (metadata: RecordMetadata, exception: Exception) => Option(exception) match {
      case None      => println(s"Message sent to partition: ${metadata.partition()}, offset: ${metadata.offset()}")
      case Some(e)   => println(s"Failed to send message to Kafka topic $topic", e)
    })
  }

  override def close(): Unit = producer.close()
}
