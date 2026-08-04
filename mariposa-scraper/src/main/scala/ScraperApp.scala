import io.circe.generic.codec.DerivedAsObjectCodec.deriveCodec
import io.circe.syntax.EncoderOps
import org.apache.kafka.clients.producer.ProducerConfig
import org.jsoup.Jsoup
import sttp.client3._
import sttp.client3.circe.asJson

object ScraperApp extends App {
  if (args.isEmpty) {
    println("Usage:   java -jar mariposa-scraper.jar topicName [optKafkaPropsFile]")
    println("Example: java -jar mariposa-scraper.jar temp-topic")
    println("Example: java -jar mariposa-scraper.jar temp-topic /path/to/kafka.properties")
    println("Example for SASL/SSL: java -Djava.security.auth.login.config=/path/to/kafka_client_jaas.conf " +
      "-jar mariposa-scraper.jar temp-topic /path/to/kafka.properties")
    sys.exit(1)
  }
  
  private val topic = args.head
  private val file = args.tail.headOption 
  private val http = HttpURLConnectionBackend()
  private val kafka = new KafkaPublisher(Map(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG -> "node49.host:9092"), file)
  
  println("=== Mariposa Scraper Example ===")

  try {
    exampleFetchAndParseJson(http, kafka)
    exampleFetchAndParseHtml(http, kafka)
  } finally {
    http.close()
    kafka.close()
  }

  private def exampleFetchAndParseJson(http: SttpBackend[Identity, Any], kafka: KafkaPublisher): Unit = {
    case class MambaResponse(title: String, description: String, keywords: String, metaRobots: String, header: String)
    case class KafkaMessage(title: String, message: String)

    println("Fetch: https://www.mamba.ru/api/seo/pages-meta?url=%2Fru")
    val response = basicRequest
      .get(uri"https://www.mamba.ru/api/seo/pages-meta?url=%2Fru")
      .response(asJson[MambaResponse])
      .send(http)
      .body

    response match {
      case Right(mambaResponse) =>
        println(s"\n✅ $mambaResponse\n")
        val msg = KafkaMessage(mambaResponse.title, mambaResponse.description)
        kafka.publish(topic, None, msg.asJson.noSpaces)
      case Left(error) =>
        println(s"Error: $error")
    }
  }

  private def exampleFetchAndParseHtml(http: SttpBackend[Identity, Any], kafka: KafkaPublisher): Unit = {
    case class YandexResponse(emoticon: String, statusMessage: String, description: String, buttonText: String)
    case class KafkaMessage(title: String, message: String)

    println("Fetch: https://mc.yandex.ru/metrika/match.html")
    val response = basicRequest
      .get(uri"https://mc.yandex.ru/metrika/match.html")
      .response(asString)
      .send(http)
      .body

    response match {
      case Right(html) =>
        val div = Jsoup.parse(html).select(".main").first()
        val yandexResponse = YandexResponse(
          div.select("h1").text(),
          div.select("h3").text(),
          div.select("p").text(),
          div.select("button").text(),
        )

        println(s"\n✅ $yandexResponse\n")
        val msg = KafkaMessage(yandexResponse.emoticon, yandexResponse.description)
        kafka.publish(topic, None, msg.asJson.noSpaces)
      case Left(error) =>
        println(s"Error: $error")
    }
  }
}
