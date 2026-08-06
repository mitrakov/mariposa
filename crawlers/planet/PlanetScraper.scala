import io.circe.JsonObject
import io.circe.syntax.EncoderOps
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.kafka.common.config.{SaslConfigs, SslConfigs}
import org.apache.kafka.common.serialization.StringSerializer
import org.apache.kafka.common.security.auth.SecurityProtocol.SASL_SSL
import org.apache.kafka.common.config.SaslConfigs.DEFAULT_SASL_MECHANISM
import org.jsoup.Jsoup
import sttp.client4.{basicRequest, DefaultSyncBackend, UriContext}
import java.time.Instant
import java.util.Properties
import scala.jdk.CollectionConverters.CollectionHasAsScala

/*
add to build.sbt: libraryDependencies ++= Seq(
  "org.jsoup" % "jsoup" % "1.23.1",
  "com.softwaremill.sttp.client4" %% "circe" % "4.0.26",
  "io.circe" %% "circe-generic" % "0.14.10",
  "org.apache.kafka" % "kafka-clients" % "4.2.0",
)
*/
class PlanetScraper {
  val jksPassword: String = sys.env.getOrElse("JKS_PASSWORD", throw new Exception("Define export JKS_PASSWORD=..."))
  val targetTopic = "planet-import"

  def run(): Unit = {
    println("=== [Mariposa] Executing LovePlanet Scraper Job ===")
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

    try {
      // Bucle secuencial idéntico a tu script de Python (0 a 1000 páginas indexadas)
      for (page <- 0 to 1000) {
        println(s"\n--- Scraping Index Page $page ---")
        val indexRequest = basicRequest
          .get(uri"https://loveplanet.ru/a-search/d-1/p-$page")
          .header("User-Agent", "Mozilla/5.0")
          .send(http)

        indexRequest.body match {
          case Right(html) =>
            val soup = Jsoup.parse(html)
            val containers = soup.select("div.buser_usinfo").asScala

            for (container <- containers) {
              val linkTag = container.select("a.buser_usname").first()

              if (linkTag != null && linkTag.hasAttr("href")) {
                val href = linkTag.attr("href")

                // Expresión regular idéntica a tu re.compile(r"^/page/\w+/frl-2$")
                if (href.matches("^/page/\\w+/frl-2$")) {
                  val fullProfileUrl = s"https://loveplanet.ru$href"
                  println(s"\nProcessing profile: $fullProfileUrl")

                  val profileDataOpt = parseProfilePage(http, fullProfileUrl)

                  profileDataOpt.foreach { profileData =>
                    // Agregamos la estampa de tiempo dinámica obligatoria para Data Science
                    val finalJson = profileData
                      .add("api_capture_date", Instant.now().toString.asJson)
                      .asJson
                      .noSpaces

                    println(s"$finalJson")

                    val record = new ProducerRecord[String, String](targetTopic, null, finalJson)
                    producer.send(record, (metadata, err) => Option(err) match {
                      case None =>
                        println(s"Item $href delivered [partition ${metadata.partition()}] at offset ${metadata.offset()}")
                      case Some(e) =>
                        println(s"Failed to send $href to Kafka: ${e.getMessage}")
                    })
                  }
                  Thread.sleep(1500) // Mantener delay de 1.5s idéntico a Python para evitar bloqueos
                }
              }
            }

          case Left(err) =>
            println(s"Error fetching index page $page: $err")
        }
      }
    } catch {
      case e: Exception => println(s"Fatal error inside loop execution: ${e.getMessage}")
    } finally {
      producer.flush()
      producer.close()
      http.close()
    }
  }

  // Simulación rápida de tu función de transliteración y limpieza para llaves compatibles con Hive
  // 💡 Mapeo exacto de tu diccionario de Python a un Map nativo de Scala
  private val translations: Map[String, String] = Map(
    "внешность" -> "appearance",
    "отношения" -> "status",
    "дети" -> "children",
    "домашние_животные" -> "pets",
    "жилищные_условия" -> "housing",
    "наличие_автомобиля" -> "has_car",
    "образование" -> "education",
    "учебное_заведение" -> "university",
    "год_выпуска" -> "graduate_year",
    "доход" -> "income",
    "сфера_деятельности" -> "industry",
    "должность" -> "job",
    "курение" -> "smoking",
    "алкоголь" -> "alcohol",
    "знание_языков" -> "languages",
    "спорт" -> "sports",
    "ваше_образование" -> "your_education",
    "любимая_музыка" -> "favorite_music",
    "любимые_фильмы" -> "favorite_movies",
    "любимые_книги" -> "favorite_books",
    "любимые_блюда" -> "favorite_dishes",
    "самое_хорошее_в_жизни" -> "best_thing",
    "самое_ужасное_в_жизни" -> "worst_thing",
    "какие_качества_вы_цените_в_людях" -> "valued_qualities",
    "что_вы_могли_бы_простить_а_что_нет" -> "what_forgive",
    "ваши_достоинства" -> "strengths",
    "ваши_недостатки" -> "weaknesses",
    "чем_интересна_ваша_работа" -> "job_interesting",
    "самый_авантюрный_поступок" -> "adventure",
    "что_вам_нравится_или_не_нравится_в_телевизоре" -> "tv",
    "как_вы_относитесь_к_мату" -> "profanity",
    "любимые_города_и_страны" -> "favorite_cities",
    "любимые_места" -> "favorite_places",
    "любимые_занятия" -> "favorite_hobby",
    "какое_место_занимает_в_вашей_жизни_религия" -> "religion"
  )

  // 💡 Función auxiliar de transliteración para llaves desconocidas (Fallback)
  private def transliterateToAscii(text: String): String = {
    val cyrillicTranslit = Map(
      'а' -> "a", 'б' -> "b", 'в' -> "v", 'г' -> "g", 'д' -> "d", 'е' -> "e", 'ё' -> "yo",
      'ж' -> "zh", 'з' -> "z", 'и' -> "i", 'й' -> "y", 'к' -> "k", 'л' -> "l", 'м' -> "m",
      'н' -> "n", 'о' -> "o", 'п' -> "p", 'р' -> "r", 'с' -> "s", 'т' -> "t", 'у' -> "u",
      'ф' -> "f", 'х' -> "kh", 'ц' -> "ts", 'ч' -> "ch", 'ш' -> "sh", 'щ' -> "shch",
      'ъ' -> "", 'ы' -> "y", 'ь' -> "", 'э' -> "e", 'ю' -> "yu", 'я' -> "ya"
    )
    text.map(char => cyrillicTranslit.getOrElse(char, char.toString)).mkString
  }

  // 💡 El método principal clean_hive_key idéntico a tu lógica de Python
  private def cleanHiveKey(prefix: String, rawKey: String): String = {
    // Normalizamos el string: lowercase, trim, espacios a guiones bajos y removemos caracteres especiales
    val normalizedKey = rawKey.toLowerCase.trim
      .replaceAll(" ", "_")
      .replaceAll("[^a-z0-9_а-яё]", "")

    val finalKey = translations.get(normalizedKey) match {
      case Some(translated) => translated
      case None             => transliterateToAscii(normalizedKey)
    }

    s"${prefix}_$finalKey"
  }
  
  // 💡 Sub-parser de páginas de perfil desarrollado nativamente con Jsoup y Circe
  private def parseProfilePage(http: sttp.client4.SyncBackend, url: String): Option[JsonObject] = {
    try {
      val response = basicRequest
        .get(uri"$url")
        .header("User-Agent", "Mozilla/5.0")
        .send(http)

      if (response.code.code != 200) {
        println(s"Failed to fetch profile: $url (Status: ${response.code})")
        return None
      }

      val html = response.body.getOrElse(return None)
      val soup = Jsoup.parse(html)

      // Extracción limpia de campos DOM selectores CSS nativos
      val displayName = Option(soup.select("span.fbold.fsize20").first()).map(_.text()).getOrElse("")

      val mainPhotoUrl = Option(soup.select("div[class*=prof-photo] img").first())
        .filter(_.hasAttr("src")).map(_.attr("src")).getOrElse("")

      var city = ""
      var visitorsCount = 0
      val locationBox = soup.select("div.blue_14").first()
      if (locationBox != null) {
        city = Option(locationBox.select("span").first()).map(_.text()).getOrElse("")
        val visitorsDiv = locationBox.select("div[class*=visiters], div[class*=blue_g]").first()
        if (visitorsDiv != null) {
          val txt = visitorsDiv.text().trim
          if (txt.forall(_.isDigit) && txt.nonEmpty) visitorsCount = txt.toInt
        }
      }

      val statusText = Option(soup.select("div[class*=prof-status]").first()).map(_.text()).getOrElse("")

      val interests = soup.select("div#tag-container a").asScala
        .map(_.text().trim).filter(_.nonEmpty).toVector

      // Selectores avanzados utilizando la potente búsqueda por texto propio de Jsoup (idéntico a re.compile en BeautifulSoup)
      val seekingText = Option(soup.select("div:containsOwn(Я ищу)").first())
        .map(div => div.nextElementSibling().text()).getOrElse("")

      val aboutText = Option(soup.select("div:containsOwn(Свободно о себе)").first())
        .map(div => div.nextElementSibling().text()).getOrElse("")

      val targetSearchText = Option(soup.select("div:containsOwn(Кого я хочу найти)").first())
        .map(div => div.nextElementSibling().text()).getOrElse("")

      // 💡 APLANAMIENTO DINÁMICO (Flattening): Inyectamos todo directo a un JsonObject intermedio de Circe
      // Esto reemplaza los diccionarios dinámicos anidados de Python (personal_details y self_portrait)
      var jsonMap = JsonObject(
        "name_age"      -> displayName.asJson,
        "photo_url"     -> mainPhotoUrl.asJson,
        "city"          -> city.asJson,
        "visitors"      -> visitorsCount.asJson,
        "quote"         -> statusText.asJson,
        "interests"     -> interests.asJson,
        "seeking"       -> seekingText.asJson,
        "about"         -> aboutText.asJson,
        "target_search" -> targetSearchText.asJson,
        "profile_url"   -> url.asJson
      )

      // Sección "Личная информация"
      val infoSection = soup.select("div:containsOwn(Личная información), div:containsOwn(Личная информация)").first()
      if (infoSection != null) {
        val infoUl = infoSection.nextElementSibling()
        if (infoUl != null && infoUl.tagName() == "ul") {
          for (li <- infoUl.select("li.flex").asScala) {
            val labelTag = li.select("label").first()
            if (labelTag != null) {
              val rawKey = labelTag.text().stripSuffix(":")
              val flatKey = cleanHiveKey("personal", rawKey)

              val sportBox = li.select("div.xcloud-box").first()
              if (sportBox != null) {
                val sportsList = sportBox.select("span").asScala.map(_.text().trim).toVector
                jsonMap = jsonMap.add(flatKey, sportsList.asJson)
              } else {
                val valDiv = li.select("div").first()
                val value = if (valDiv != null) valDiv.text().trim else ""
                jsonMap = jsonMap.add(flatKey, value.asJson)
              }
            }
          }
        }
      }

      // Sección "Автопортрет"
      val portraitSection = soup.select("div:containsOwn(Автопортрет)").first()
      if (portraitSection != null) {
        val portraitUl = portraitSection.nextElementSibling()
        if (portraitUl != null && portraitUl.tagName() == "ul") {
          for (li <- portraitUl.select("li.flex").asScala) {val labelTag = li.select("label").first()
            if (labelTag != null) {val rawKey = labelTag.text().stripSuffix(":")
              val flatKey = cleanHiveKey("portrait", rawKey)
              val valDiv = li.select("div").first()
              val value = if (valDiv != null) valDiv.text().trim else ""
              jsonMap = jsonMap.add(flatKey, value.asJson)
            }
          }
        }
      }
      Some(jsonMap)
    } catch { case e: Exception =>
      println(s"Error parsing subpage profile $url: ${e.getMessage}")
      None
    }
  }
}
