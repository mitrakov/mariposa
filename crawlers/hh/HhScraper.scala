import io.circe._
import io.circe.parser.parse
import io.circe.syntax.EncoderOps
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.kafka.common.config.{SaslConfigs, SslConfigs}
import org.apache.kafka.common.serialization.StringSerializer
import org.apache.kafka.common.security.auth.SecurityProtocol.SASL_SSL
import org.apache.kafka.common.config.SaslConfigs.DEFAULT_SASL_MECHANISM
import sttp.client4.{basicRequest, DefaultSyncBackend, UriContext}
import java.io.PrintWriter
import java.time.Instant
import java.util.Properties
import scala.io.Source

/*
libraryDependencies ++= Seq(
  "org.jsoup" % "jsoup" % "1.23.1",
  "com.softwaremill.sttp.client4" %% "circe" % "4.0.26",
  "io.circe" %% "circe-generic" % "0.14.10",
  "org.apache.kafka" % "kafka-clients" % "4.2.0",
)
*/
class HhScraper {
  val jksPassword: String = sys.env.getOrElse("JKS_PASSWORD", throw new Exception("Define export JKS_PASSWORD=..."))
  val targetTopic = "hh-import"
  val batchSize = 1000000
  val idFile = "id.txt"
  val sleepMsec = 3500     // update this param to catch up the ID!
  
  def run(): Unit = {
    println("=== [Mariposa] Executing HeadHunter Scraper Job ===")
    System.setProperty("java.security.auth.login.config", "/opt/kafka/config/kafka_jaas.conf")

    val kafkaProps = new Properties()
    kafkaProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "node143.host:9092")
    kafkaProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    kafkaProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    kafkaProps.put("security.protocol", SASL_SSL.name)
    kafkaProps.put(SaslConfigs.SASL_MECHANISM, DEFAULT_SASL_MECHANISM)
    kafkaProps.put(SaslConfigs.SASL_KERBEROS_SERVICE_NAME, "kafka")
    kafkaProps.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "/opt/vault/certs/truststore.jks")
    kafkaProps.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, jksPassword)

    val producer = new KafkaProducer[String, String](kafkaProps)
    val http = DefaultSyncBackend()
    val curId = readCurrentId()
    
    try {
      // Bucle Batch controlado
      var errCount = 0
      for (vacId <- curId to (curId + batchSize)) {
        println(s"\nProcessing vacancy ID $vacId")

        val url = s"https://hh.ru/shards/vacancy/related_vacancies?vacancyId=$vacId"
        val response = basicRequest
          .get(uri"$url")
          .header("User-Agent", "Mozilla/5.0")
          .send(http)

        if (response.code.code != 200) {
          println(s"Failed to fetch $url (Status: ${response.code})")
          errCount += 1
          if (errCount >= 99) {
            println(s"Too many errors to call API ($errCount). Exiting production loop...")
            return
          }
        } else {
          errCount = 0 // Reseteamos contador de errores consecutivos

          response.body match {
            case Right(jsonString) =>
              // Parseamos el string crudo a un Json manipulable por Circe
              parse(jsonString) match {
                case Right(json) =>
                  // 💡 Extraemos el array "vacancies" usando cursores dinámicos
                  val vacanciesArray = json.hcursor.downField("vacancies").as[List[Json]].getOrElse(Nil)

                  for (vacancyJson <- vacanciesArray) {
                    val msgObject = extractMessage(vacancyJson.hcursor, vacId)
                    val payload = msgObject.asJson.noSpaces
                    println(s"\n$payload")

                    val record = new ProducerRecord[String, String](targetTopic, null, payload)
                    producer.send(record, (metadata, err) => Option(err) match {
                      case None =>
                        // 💡 Al confirmar entrega en Kafka, incrementamos y persistimos el ID en id.txt
                        writeCurrentId(vacId + 1)
                        println(s"ID=$vacId delivered to $targetTopic [partition ${metadata.partition()}] at offset ${metadata.offset()}")
                      case Some(e) =>
                        println(s"❌ Failed to send vacancy $vacId to Kafka: ${e.getMessage}")
                    })
                  }
                case Left(parseErr) => println(s"Circe parsing failed for payload string: $parseErr")
              }
            case Left(httpErr) => println(s"STTP Transport error body missing: $httpErr")
          }
        }

        producer.flush() // flush inmediato por iteración para asegurar la persistencia secuencial del ID
        Thread.sleep(sleepMsec)
      }
    } catch {
      case e: Exception => println(s"Fatal exception inside master HH execution stream: ${e.getMessage}")
    } finally {
      producer.flush()
      producer.close()
      http.close()
    }
  }

  private def readCurrentId(): Int = {
    val src = Source.fromFile(idFile)
    try {src.mkString.toInt} finally {src.close()}
  }

  private def writeCurrentId(id: Int): Unit = {
    val writer = new PrintWriter(idFile)
    try { writer.print(id) } finally { writer.close() }
  }

  // 💡 EL PARSER DE EXTRACCIÓN DINÁMICA: Reemplaza completamente los mapeos de diccionarios de Python
  private def extractMessage(c: HCursor, apiVacancyId: Int): JsonObject = {
    // Funciones auxiliares de navegación estricta
    def str(path: HCursor => ACursor): Json =
      path(c).as[String].map(Json.fromString).getOrElse(Json.Null)

    def num(path: HCursor => ACursor): Json =
      path(c).as[Long].map(Json.fromLong).getOrElse(Json.Null)

    def doubleNum(path: HCursor => ACursor): Json =
      path(c).as[Double].flatMap(d => Json.fromDouble(d).toRight(DecodingFailure("Invalid double", path(c).history))).getOrElse(Json.Null)

    def bool(path: HCursor => ACursor): Json =
      path(c).as[Boolean].map(Json.fromBoolean).getOrElse(Json.Null)

    // 💡 SOLUCIÓN DEFINITIVA: Extraemos el arreglo de strings completo [...] de la API en lugar de solo el primer string.
    val workFormatsArr = c.downField("workFormats").downArray.downField("workFormatsElement").as[Vector[String]].getOrElse(Vector.empty)
    val workingHoursArr = c.downField("workingHours").downArray.downField("workingHoursElement").as[Vector[String]].getOrElse(Vector.empty)
    val scheduleByDaysArr = c.downField("workScheduleByDays").downArray.downField("workScheduleByDaysElement").as[Vector[String]].getOrElse(Vector.empty)
    val experimentalArr = c.downField("experimentalModes").downArray.downField("experimentalMode").as[Vector[String]].getOrElse(Vector.empty)
    val metroName = c.downField("address").downField("metroStations").downField("metro").downArray.downField("name").as[String].getOrElse(null)

    JsonObject(
      "vacancy_id"            -> num(_.downField("vacancyId")),
      "published"             -> str(_.downField("publicationTime").downField("$")),
      "name"                  -> str(_.downField("name")),
      "area_name"             -> str(_.downField("area").downField("name")),
      "salary_from"           -> num(_.downField("compensation").downField("from")),
      "salary_to"             -> num(_.downField("compensation").downField("to")),
      "currency"              -> str(_.downField("compensation").downField("currencyCode")),
      "gross"                 -> bool(_.downField("compensation").downField("gross")),
      "work_formats"          -> workFormatsArr.asJson,
      "employment"            -> str(_.downField("employmentForm")),
      "working_hours"         -> workingHoursArr.asJson,
      "schedule_by_days"      -> scheduleByDaysArr.asJson,
      "company_name"          -> str(_.downField("company").downField("name")),
      "metro"                 -> (if (metroName != null) Json.fromString(metroName) else Json.Null),
      "district"              -> str(_.downField("address").downField("districtDto").downField("name")),
      "address"               -> str(_.downField("address").downField("displayName")),
      "created"               -> str(_.downField("creationTime")),
      "schedule"              -> str(_.downField("@workSchedule")),
      "experience"            -> str(_.downField("workExperience")),
      "user_test"             -> bool(_.downField("userTestPresent")),
      "internship"            -> bool(_.downField("internship")),
      "night_shifts"          -> bool(_.downField("nightShifts")),
      "accept_labor_contract" -> bool(_.downField("acceptLaborContract")),
      "experimental"          -> experimentalArr.asJson,
      "responses"             -> num(_.downField("responsesCount")),
      "responses_total"       -> num(_.downField("totalResponsesCount")),
      "company_id"            -> num(_.downField("company").downField("id")),
      "company_category"      -> str(_.downField("company").downField("@category")),
      "company_url"           -> str(_.downField("company").downField("companySiteUrl")),
      "company_acc"           -> bool(_.downField("company").downField("accreditedITEmployer")),
      "company_reviews"       -> doubleNum(_.downField("company").downField("employerReviews").downField("totalRating")),
      "company_reviews_cnt"   -> num(_.downField("company").downField("employerReviews").downField("reviewsCount")),
      "salary_per_mode_from"  -> num(_.downField("compensation").downField("perModeFrom")),
      "salary_per_mode_to"    -> num(_.downField("compensation").downField("perModeTo")),
      "salary_frequency"      -> str(_.downField("compensation").downField("frequency")),
      "salary_mode"           -> str(_.downField("compensation").downField("mode")),
      "area_id"               -> num(_.downField("area").downField("@id")),
      "snippet_req"           -> str(_.downField("snippet").downField("req")),
      "snippet_resp"          -> str(_.downField("snippet").downField("resp")),
      "snippet_cond"          -> str(_.downField("snippet").downField("cond")),
      "snippet_skill"         -> str(_.downField("snippet").downField("skill")),
      "api_vacancy_id"        -> Json.fromInt(apiVacancyId),
      "api_capture_date"      -> Json.fromString(Instant.now().toString)
    )
  }
}
