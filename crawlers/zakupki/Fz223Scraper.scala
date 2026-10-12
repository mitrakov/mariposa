import io.circe.syntax._
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.kafka.common.config.SaslConfigs.DEFAULT_SASL_MECHANISM
import org.apache.kafka.common.config.{SaslConfigs, SslConfigs}
import org.apache.kafka.common.security.auth.SecurityProtocol.SASL_SSL
import org.apache.kafka.common.serialization.StringSerializer
import org.jsoup.Jsoup
import sttp.client4.httpclient.HttpClientSyncBackend
import sttp.client4.{UriContext, basicRequest}
import io.circe.Json
import java.time.Instant
import scala.jdk.CollectionConverters._
import java.io.PrintWriter
import java.net.http.HttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Properties
import javax.net.ssl.{SSLContext, X509TrustManager}
import scala.io.Source
import scala.util.Try

/*
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic zakupki-fz223-import
JKS_PASSWORD=... java -jar /home/hadoop/mariposa-scraper-assembly-*.jar /home/hadoop/apps/Fz223Scraper.scala
build.sbt: libraryDependencies ++= Seq(
  "org.jsoup" % "jsoup" % "1.23.1", "com.softwaremill.sttp.client4" %% "circe" % "4.0.26",
  "io.circe" %% "circe-generic" % "0.14.10", "org.apache.kafka" % "kafka-clients" % "4.2.0",
)
*/
class Fz223Scraper {
  val jksPassword: String = sys.env.getOrElse("JKS_PASSWORD", throw new Exception("Define export JKS_PASSWORD=..."))
  val kafkaServer = "n01:9092"
  val targetTopic = "zakupki-fz223-import"
  val batchSize = 1000000
  val idFile = "fz223-id.txt"
  val sleepMsec = 6000     // update this param to catch up the ID!

  def run(): Unit = {
    println("=== [Mariposa] Executing Zakupki FZ-223 Scraper Job ===")
    System.setProperty("java.security.auth.login.config", "/opt/kafka/config/kafka_jaas.conf")

    // 2. Carga dinámica de propiedades del archivo kafka.properties
    val kafkaProps = new Properties()
    kafkaProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, kafkaServer)
    kafkaProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    kafkaProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    kafkaProps.put("security.protocol", SASL_SSL.name)
    kafkaProps.put(SaslConfigs.SASL_MECHANISM, DEFAULT_SASL_MECHANISM)
    kafkaProps.put(SaslConfigs.SASL_KERBEROS_SERVICE_NAME, "kafka")
    kafkaProps.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "/opt/vault/certs/truststore.jks")
    kafkaProps.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, jksPassword)

    val producer = new KafkaProducer[String, String](kafkaProps)

    // make "unsafe" HTTPS client. Inicializamos el contexto SSL inyectando nuestro TrustManager ciego
    val sslContext = SSLContext.getInstance("TLS")
    sslContext.init(null, Array(
      new X509TrustManager {
        override def checkClientTrusted(chain: Array[X509Certificate], authType: String): Unit = {}
        override def checkServerTrusted(chain: Array[X509Certificate], authType: String): Unit = {}
        override def getAcceptedIssuers: Array[X509Certificate] = Array.empty
      }
    ), new SecureRandom())

    // Construimos el HttpClient nativo de Java deshabilitando las alertas de certificados
    // 🚀 Inyectamos este cliente personalizado en el motor de STTP
    val http = HttpClientSyncBackend.usingClient(HttpClient.newBuilder().sslContext(sslContext).build())

    val curId = readCurrentId()
    var errCount = 0

    // 3. Bucle de extracción principal del Pipeline
    for (id <- curId to (curId + batchSize)) {
      try {
        Thread.sleep(sleepMsec)
        println(s"\nProcessing FZ-223 Registration Number: $id")

        val url = s"https://zakupki.gov.ru/223/purchase/public/purchase/info/common-info.html?regNumber=$id"

        val response = basicRequest
          .get(uri"$url")
          .header("User-Agent", "Mozilla/5.0")
          .send(http)

        if (response.code.code == 404) {
          println(s"Not found: $id (404). Skipping...")
        } else if (response.code.code != 200) {
          println(s"Failed to fetch $id (Status: ${response.code})")
          errCount += 1
          if (errCount >= 100) {
            println(s"💥 Circuit-breaker activo ($errCount errores). Deteniendo proceso...")
            producer.flush()
            producer.close()
            http.close()
            return
          }
        } else {
          errCount = 0 // Reseteamos contador tras una respuesta 200 limpia

          response.body match {
            case Right(htmlContent) =>
              val parsedData = parseHtml(htmlContent, id)

              // Validamos si la página web contenía datos reales escaneados
              if (!parsedData.contains("reg_number")) {
                println(s"Page for ID $id does not contain valid reg_number data. Skipping push...")
              } else {
                // Enriquecimiento dinámico del JsonObject antes del envío
                val finalPayload = parsedData.asJson.noSpaces

                println(s"Sending to Kafka: $finalPayload")
                val record = new ProducerRecord[String, String](targetTopic, null, finalPayload)

                producer.send(record, (metadata, err) => Option(err) match {
                  case None =>
                    println(s"ID=$id committed successfully to partition [${metadata.partition()}] at offset [${metadata.offset()}]")
                  case Some(e) =>
                    println(s"❌ Failed transmission to Kafka for ID $id: ${e.getMessage}")
                })
              }

              // 💡 ACTUALIZACIÓN SECUENCIAL SEGURA: Avanzamos el puntero en el hilo determinista principal
              writeCurrentId(id + 1)

            case Left(httpErr) => println(s"Transport layout error body missing: $httpErr")
          }
        }
      } catch {
        case e: Exception => println(s"Unexpected iteration error: ${e.getMessage}"); e.printStackTrace()
      }
    }

    // 💡 EFICIENCIA DE RED: Vaciamos el búfer masivo al terminar el lote entero
    println("\n=== Flushing remaining payloads to Kafka broker === ")
    producer.flush()
    producer.close()
    http.close()
    println("SUCCESS: FZ-223 Extraction pipeline finished.")
  }

  private val fieldMap = Map(
    "Реестровый номер извещения" -> "reg_number",
    "Способ осуществления закупки" -> "method",
    "Наименование закупки" -> "description",
    "Редакция" -> "revision",
    "Дата размещения извещения" -> "notice_date",
    "Дата размещения текущей редакции извещения" -> "revision_date",
    "Наименование организации" -> "customer",
    "ИНН" -> "inn",
    "КПП" -> "kpp",
    "ОГРН" -> "ogrn",
    "Место нахождения" -> "location",
    "Почтовый адрес" -> "address",
    "Контактное лицо" -> "contact_person",
    "Адрес электронной почты" -> "contact_email",
    "Контактный телефон" -> "contact_phone"
  )

  private def parseHtml(htmlContent: String, id: Long): Map[String, Json] = {
    val soup = Jsoup.parse(htmlContent)
    var data = Map[String, Json]()

    // 1. 🌍 EXTRACCIÓN DEL NÚMERO DE REGISTRO
    val regEl = soup.select(".registry-entry__header-mid__number a, div[class*='number'] a").first()
    if (regEl != null) {
      val cleanRegNumber = regEl.text().replace("№", "").replaceAll("\\s+", "").trim
      data += ("reg_number" -> Json.fromString(cleanRegNumber))
    }

    // 2. 🛡️ EXTRACCIÓN DEL STATUS
    val statusEl = soup.select(".registry-entry__header-mid__title, div[class*='header-mid'] div[class*='title']").first()
    if (statusEl != null) {
      data += ("status" -> Json.fromString(statusEl.text().trim))
    }

    // 3. 🌍 EXTRACCIÓN DE TIMEZONE (Selector Único y Estricto de la Zona Horaria)
    // Apuntamos directo al span hijo de .time-zone__value para evitar capturar el bloque del reg_number
    val tzEl = soup.select(".time-zone__value span").first()
    if (tzEl != null) {
      data += ("timezone" -> Json.fromString(tzEl.text().trim))
    } else {
      // Fallback secundario: si cambian el span, buscamos la clase de valor directa
      val tzFallback = soup.select(".time-zone__value").first()
      if (tzFallback != null) {
        data += ("timezone" -> Json.fromString(tzFallback.text().trim))
      }
    }

    // 4. 🚖 OBJETO DE LA COMPRA Y CLIENTE
    val bodyBlocks = soup.select(".registry-entry__body-block")
    for (block <- bodyBlocks.asScala) {
      val titleEl = block.select(".registry-entry__body-title").first()
      val valueEl = block.select(".registry-entry__body-value").first()

      if (titleEl != null && valueEl != null) {
        val titleText = titleEl.text().trim
        val valueText = valueEl.text().trim

        if (titleText == "Объект закупки") {
          data += ("description" -> Json.fromString(valueText))
        } else if (titleText == "Заказчик") {
          data += ("customer" -> Json.fromString(valueText))

          // ⚡ EXTRACTOR INTELIGENTE DE INN, КПП, ОГРН DESDE EL LINK DEL CLIENTE
          val linkEl = valueEl.select("a[href]").first()
          if (linkEl != null) {
            val href = linkEl.attr("href")
            // Expresiones regulares para capturar los parámetros de la URL estatal
            "inn=(\\d+)".r.findFirstMatchIn(href).foreach(m => data += ("inn" -> Json.fromString(m.group(1))))
            "kpp=(\\d+)".r.findFirstMatchIn(href).foreach(m => data += ("kpp" -> Json.fromString(m.group(1))))
            "ogrn=(\\d+)".r.findFirstMatchIn(href).foreach(m => data += ("ogrn" -> Json.fromString(m.group(1))))
          }
        }
      }
    }

    // 5. 💰 EXTRACCIÓN DE PRECIO
    val priceValEl = soup.select(".price-block__value").first()
    if (priceValEl != null) {
      val rawPrice = priceValEl.text().trim
      // Limpia espacios duros no-breaking spaces (\u00a0) y caracteres de moneda
      val cleanPrice = rawPrice.replaceAll("[^\\d,.]", "").replace(",", ".").trim
      Try(cleanPrice.toDouble).toOption.foreach { priceDouble =>
        data += ("price" -> Json.fromDoubleOrNull(priceDouble))
      }
    }

    // 6. 📅 EXTRACCIÓN DE FECHAS
    val dataBlocks = soup.select(".data-block .col-6, .data-block .col-12, .data-block__value")
    for (block <- dataBlocks.asScala) {
      val titleEl = block.select(".data-block__title").first()
      val valueEl = block.select(".data-block__value").first()

      if (titleEl != null && valueEl != null) {
        val titleText = titleEl.text().trim
        val valueText = valueEl.text().trim

        titleText match {
          case "Размещено" =>
            parseToIsoDate(valueText).foreach(d => data += ("publish_date" -> Json.fromString(d)))
          case "Обновлено" =>
            parseToIsoDate(valueText).foreach(d => data += ("update_date" -> Json.fromString(d)))
          case "Окончание подачи заявок" =>
            parseToIsoDate(valueText).foreach(d => data += ("finish_date" -> Json.fromString(d)))
          case _ =>
        }
      }
    }

    // 7. 🌍 FALLBACK: PARSEO SECUNDARIO POR FIELD_MAP (Por si vienen en texto plano abajo)
    val commonFields = soup.select(".common-text__title, div[class*='text__title']")
    for (titleEl <- commonFields.asScala) {
      // 💡 SOLUCIÓN: Usamos el método nativo correcto 'nextElementSibling()' de Jsoup
      val valEl = titleEl.nextElementSibling()
      if (valEl != null) {
        val cleanKey = titleEl.text().replace(":", "").trim
        fieldMap.get(cleanKey).foreach { mappedKey =>
          // Solo agregamos si no lo extrajo el analizador principal
          if (!data.contains(mappedKey)) {
            data += (mappedKey -> Json.fromString(valEl.text().trim))
          }
        }
      }
    }

    // 7. 🔒 METADATOS DE AUDITORÍA Y CONTROL
    data += ("api_id" -> Json.fromLong(id))
    data += ("api_capture_date" -> Json.fromString(Instant.now().toString))
    data
  }

  // Función auxiliar para transformar "08.10.2026" a "2026-10-08" en Scala
  private def parseToIsoDate(dateText: String): Option[String] = {
    try {
      val formatter = java.time.format.DateTimeFormatter.ofPattern("dd.MM.yyyy")
      val localDate = java.time.LocalDate.parse(dateText.trim, formatter)
      Some(localDate.toString) // Devuelve formato ISO "YYYY-MM-DD" nativo
    } catch {
      case _: Exception => None
    }
  }

  private def readCurrentId(): Long = {
    val src = Source.fromFile(idFile)
    try {src.mkString.toLong} finally {src.close()}
  }

  private def writeCurrentId(id: Long): Unit = {
    val writer = new PrintWriter(idFile)
    try { writer.print(id) } finally { writer.close() }
  }
}
