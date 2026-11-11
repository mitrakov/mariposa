import io.circe.JsonObject
import io.circe.syntax.EncoderOps
import org.jsoup.Jsoup
import sttp.client4.{DefaultSyncBackend, UriContext, basicRequest}
import java.sql.{Connection, DriverManager, PreparedStatement, Types}
import java.time.Instant
import scala.jdk.CollectionConverters.CollectionHasAsScala
import scala.util.Using.Manager

/*
kafka-topics.sh --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties --create --topic planet-import
JKS_PASSWORD=... java -jar /home/hadoop/mariposa-scraper-assembly-*.jar /home/hadoop/apps/PlanetScraper.scala
build.sbt: libraryDependencies ++= Seq(
  "org.jsoup" % "jsoup" % "1.23.1", "com.softwaremill.sttp.client4" %% "circe" % "4.0.26",
  "io.circe" %% "circe-generic" % "0.14.10", "org.apache.kafka" % "kafka-clients" % "4.2.0",
  "org.xerial" % "sqlite-jdbc" % "3.54.1.0",
)
*/
class PlanetScraperDB {
  val dbPath = "planet.db"
  val sleepMsec = 2000
  
  run()

  def run(): Unit = {
    while (true) {
      run_()
      Thread.sleep(24 * 3600 * 1000)
    }
  }

  private def run_(): Unit = {
    println("=== LovePlanet Scraper Job (SQLite Modular Mode) ===")
    val upsert: String =
      """INSERT INTO profile (
        |  id, photo, gender, name, age, city, children, status, seeking, alcohol, languages, about, quote, target_search, interests,
        |  payload
        |) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        |ON CONFLICT(id) DO UPDATE SET
        |  photo      = excluded.photo,
        |  gender     = excluded.gender,
        |  name       = excluded.name,
        |  age        = excluded.age,
        |  city       = excluded.city,
        |  children   = excluded.children,
        |  status     = excluded.status,
        |  seeking    = excluded.seeking,
        |  alcohol    = excluded.alcohol,
        |  languages  = excluded.languages,
        |  about      = excluded.about,
        |  quote      = excluded.quote,
        |  target_search = excluded.target_search,
        |  interests  = excluded.interests,
        |  payload    = excluded.payload,
        |  updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        |  ;""".stripMargin
    Manager { use =>
      val conn = use(DriverManager.getConnection(s"jdbc:sqlite:$dbPath"))
      initDb(conn)
      val upsertStmt = use(conn.prepareStatement(upsert))
      val http = use(DefaultSyncBackend())

      for (page <- 0 to 1000) {
        scrapeIndexPage(http, upsertStmt, page)
      }
      println("DONE.\n")
    } recover { case e: Exception => println(s"Fatal scraper error: ${e.getMessage}") }
  }

  private def scrapeIndexPage(
                               http: sttp.client4.SyncBackend,
                               upsertStmt: PreparedStatement,
                               page: Int
                             ): Unit = {
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
            if (href.matches("^/page/\\w+/frl-2$")) {
              val fullProfileUrl = s"https://loveplanet.ru$href"
              processSingleProfile(http, upsertStmt, fullProfileUrl)
              Thread.sleep(sleepMsec)
            }
          }
        }
      case Left(err) =>
        println(s"Error fetching index page $page: $err")
    }
  }

  private def processSingleProfile(
                                    http: sttp.client4.SyncBackend,
                                    upsertStmt: PreparedStatement,
                                    profileUrl: String
                                  ): Unit = {
    println(s"Processing profile: $profileUrl")
    for {
      rawJsonObj <- parseProfilePage(http, profileUrl)
      stampedObj  = rawJsonObj.add("api_capture_date", Instant.now().toString.asJson)
      record     <- extractProfileRecord(profileUrl, stampedObj)
    } {
      upsertProfile(upsertStmt, record)
      println(s"Upserted ${record.name} (${record.age}, ${record.city}) -> SQLite")
    }
  }

  private def extractProfileRecord(
                                    profileUrl: String,
                                    jsonObj: JsonObject
                                  ): Option[ProfileRecord] = {
    def getStr(key: String): Option[String] =
      jsonObj(key).flatMap(_.asString).map(_.trim).filter(_.nonEmpty)

    def getArrayAsCsv(key: String): Option[String] =
      jsonObj(key)
        .flatMap(_.asArray)
        .map(_.flatMap(_.asString).map(_.trim).filter(_.nonEmpty))
        .filter(_.nonEmpty)
        .map(_.mkString(", "))

    // Parse "Дарья, 25" -> ("Дарья", 25)
    val (parsedName, parsedAge) = getStr("name_age") match {
      case Some(raw) =>
        val parts = raw.split(",").map(_.trim)
        val namePart = parts.headOption.getOrElse("")
        val agePart = parts.lift(1).flatMap(_.filter(_.isDigit).toIntOption).getOrElse(0)
        (namePart, agePart)
      case None => ("", 0)
    }

    // Validate required NOT NULL / CHECK fields before hitting SQLite
    val cityOpt = getStr("city")
    if (parsedName.isEmpty || parsedAge < 17 || cityOpt.isEmpty) {
      println(s"Skipping invalid/incomplete profile $profileUrl (name='$parsedName', age=$parsedAge, city=$cityOpt)")
      return None
    }

    // Detect gender from JSON if available, defaulting to false (woman) for d-1 search
    val isMan = getStr("gender").exists(_.equalsIgnoreCase("man"))

    // Ensure photo matches CHECK (photo IS NULL OR photo LIKE 'https://%')
    val validPhoto = getStr("photo_url").filter(_.startsWith("https://"))

    Some(
      ProfileRecord(
        id        = profileUrl,
        photo     = validPhoto,
        gender    = isMan,
        name      = parsedName,
        age       = parsedAge,
        city      = cityOpt.get,
        children  = getStr("personal_children"),
        status    = getStr("personal_status"),
        seeking   = getStr("seeking"),
        alcohol   = getStr("personal_alcohol"),
        languages = getArrayAsCsv("personal_languages").orElse(getStr("personal_languages")),
        about     = getStr("about"),
        quote     = getStr("quote"),
        targetSearch = getStr("target_search"),
        interests = getArrayAsCsv("interests"),
        payload   = jsonObj.asJson.noSpaces
      )
    )
  }

  private def upsertProfile(stmt: PreparedStatement, r: ProfileRecord): Unit = {
    def setNullableString(idx: Int, opt: Option[String]): Unit = opt match {
      case Some(v) => stmt.setString(idx, v)
      case None    => stmt.setNull(idx, Types.VARCHAR)
    }

    stmt.setString(1, r.id)
    setNullableString(2, r.photo)
    stmt.setBoolean(3, r.gender)
    stmt.setString(4, r.name)
    stmt.setInt(5, r.age)
    stmt.setString(6, r.city)
    setNullableString(7, r.children)
    setNullableString(8, r.status)
    setNullableString(9, r.seeking)
    setNullableString(10, r.alcohol)
    setNullableString(11, r.languages)
    setNullableString(12, r.about)
    setNullableString(13, r.quote)
    setNullableString(14, r.targetSearch)
    setNullableString(15, r.interests)
    stmt.setString(16, r.payload)

    stmt.executeUpdate()
  }

  private def initDb(conn: Connection): Unit = {
    val stmt = conn.createStatement()
    try {
      stmt.execute("PRAGMA synchronous=NORMAL;")
      stmt.execute(
        """CREATE TABLE IF NOT EXISTS profile (
          |    id TEXT NOT NULL PRIMARY KEY CHECK (id LIKE 'https://%'),
          |    photo TEXT CHECK (photo IS NULL OR photo LIKE 'https://%'),
          |    gender BOOLEAN NOT NULL,
          |    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          |    age INTEGER NOT NULL CHECK (age >= 17),
          |    city TEXT NOT NULL,
          |    children TEXT,
          |    status TEXT,
          |    seeking TEXT,
          |    alcohol TEXT,
          |    languages TEXT,
          |    about TEXT,
          |    quote TEXT,
          |    target_search TEXT,
          |    interests TEXT,
          |    payload TEXT NOT NULL CHECK (json_valid(payload)),
          |    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          |    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          |    synced BOOLEAN NOT NULL DEFAULT false
          |) WITHOUT ROWID;
          |""".stripMargin
      )
      stmt.execute("CREATE INDEX IF NOT EXISTS idx_gender_children_age ON profile(gender, children, age);")
      stmt.execute("CREATE INDEX IF NOT EXISTS idx_status  ON profile(status);")
      stmt.execute("CREATE INDEX IF NOT EXISTS idx_alcohol ON profile(alcohol);")
      stmt.execute("CREATE INDEX IF NOT EXISTS idx_city    ON profile(city);")
      stmt.execute("CREATE INDEX IF NOT EXISTS idx_synced  ON profile(synced) WHERE synced = false;")
    } finally {
      stmt.close()
    }
  }

//  private def run_(): Unit = {
//    println("=== LovePlanet Scraper Job (SQLite WAL Mode) ===")
//    val conn = DriverManager.getConnection(dbPath)
//    initDb(conn)
//
//    val insertSql =
//      """INSERT INTO profiles (profile_url, capture_date, payload_json, synced_to_kafka)
//        |VALUES (?, ?, ?, 0)
//        |ON CONFLICT(profile_url) DO UPDATE SET
//        |  capture_date = excluded.capture_date,
//        |  payload_json = excluded.payload_json,
//        |  synced_to_kafka = 0""".stripMargin
//
//    val pstmt = conn.prepareStatement(insertSql)
//    val http = DefaultSyncBackend()
//
//    try {
//      for (page <- 0 to 1000) {
//        println(s"\n--- Scraping Index Page $page ---")
//        val indexRequest = basicRequest
//          .get(uri"https://loveplanet.ru")
//          .header("User-Agent", "Mozilla/5.0")
//          .send(http)
//
//        indexRequest.body match {
//          case Right(html) =>
//            val soup = Jsoup.parse(html)
//            val containers = soup.select("div.buser_usinfo").asScala
//            for (container <- containers) {
//              val linkTag = container.select("a.buser_usname").first()
//              if (linkTag != null && linkTag.hasAttr("href")) {
//                val href = linkTag.attr("href")
//                if (href.matches("^/page/\\w+/frl-2$")) {
//                  val fullProfileUrl = s"https://loveplanet.ru$href"
//                  println(s"\nProcessing profile: $fullProfileUrl")
//
//                  parseProfilePage(http, fullProfileUrl).foreach { profileData =>
//                    val now = Instant.now().toString
//                    val finalJson = profileData
//                      .add("api_capture_date", now.asJson)
//                      .asJson
//                      .noSpaces
//
//                    pstmt.setString(1, fullProfileUrl)
//                    pstmt.setString(2, now)
//                    pstmt.setString(3, finalJson)
//                    pstmt.executeUpdate()
//
//                    println(s"Saved $href to SQLite.")
//                  }
//                  Thread.sleep(sleepMsec)
//                }
//              }
//            }
//          case Left(err) =>
//            println(s"Error: $err")
//        }
//      }
//    } catch {
//      case e: Exception => println(s"Err: ${e.getMessage}")
//    } finally {
//      pstmt.close()
//      conn.close()
//      http.close()
//      println("DONE.\n")
//    }
//  }

  private lazy val translations: Map[String, String] = Map(
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
    val normalizedKey = rawKey.toLowerCase.trim.replaceAll(" ", "_").replaceAll("[^a-z0-9_а-яё]", "")

    val finalKey = translations.get(normalizedKey) match {
      case Some(translated) => translated
      case None             => transliterateToAscii(normalizedKey)
    }

    s"${prefix}_$finalKey"
  }

  // Sub-parser de páginas de perfil desarrollado nativamente con Jsoup y Circe
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
      val displayName = Option(soup.select("span.fbold.fsize20").first()).map(_.text())

      val mainPhotoUrl = Option(soup.select("div[class*=prof-photo] img").first())
        .filter(_.hasAttr("src")).map(_.attr("src"))

      var city: Option[String] = None
      var visitorsCount = 0
      val locationBox = soup.select("div.blue_14").first()
      if (locationBox != null) {
        city = Option(locationBox.select("span").first()).map(_.text())
        val visitorsDiv = locationBox.select("div[class*=visiters], div[class*=blue_g]").first()
        if (visitorsDiv != null) {
          val txt = visitorsDiv.text().trim
          if (txt.forall(_.isDigit) && txt.nonEmpty) visitorsCount = txt.toInt
        }
      }

      val quote = Option(soup.select("div[class*=prof-status]").first()).map(_.text())
      val interests = soup.select("div#tag-container a").asScala.map(_.text().trim).filter(_.nonEmpty)
      val seekingText = Option(soup.select("div:containsOwn(Я ищу)").first()).map(div => div.nextElementSibling().text())
      val aboutText = Option(soup.select("div:containsOwn(Свободно о себе)").first()).map(div => div.nextElementSibling().text())
      val targetSearchText = Option(soup.select("div:containsOwn(Кого я хочу найти)").first()).map(div => div.nextElementSibling().text())

      var jsonMap = JsonObject(
        "name_age"      -> displayName.asJson,
        "photo_url"     -> mainPhotoUrl.asJson,
        "city"          -> city.asJson,
        "visitors"      -> visitorsCount.asJson,
        "quote"         -> quote.asJson,
        "interests"     -> interests.asJson,
        "seeking"       -> seekingText.asJson,
        "about"         -> aboutText.asJson,
        "target_search" -> targetSearchText.asJson,
        "profile_url"   -> url.asJson
      )

      // Sección "Личная информация"
      val infoSection = soup.select("div:containsOwn(Личная информация)").first()
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

case class ProfileRecord(
  id: String,
  photo: Option[String],
  gender: Boolean,
  name: String,
  age: Int,
  city: String,
  children: Option[String],
  status: Option[String],
  seeking: Option[String],
  alcohol: Option[String],
  languages: Option[String],
  about: Option[String],
  quote: Option[String],
  targetSearch: Option[String],
  interests: Option[String],
  payload: String
)
