import org.apache.spark.sql.{Column, SparkSession}
import org.apache.spark.sql.functions._


// build.sbt: "org.apache.spark" %% "spark-sql"  % "4.1.1" % "provided"
// spark-submit --num-executors 5 --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar Fz223RefineJob.scala
class Fz223RefineJob {
  private val sourceTable = "zakupki.fz223_import"
  private val targetTable = "zakupki.fz223_refine"

  def run(spark: SparkSession): Unit = {
    import spark.implicits._
    println(s"[ETL]: $sourceTable -> $targetTable")

    // primary processing: remove duplicates, extract "city"
    val processedDf = spark.read.table(sourceTable)
      .filter($"reg_number".isNotNull && trim($"reg_number") =!= "")
      .dropDuplicates("reg_number")
      .withColumn("city", buildCityExtractionLogic($"address"))

    // reorder columns: reg_number, city, price, description...
    val primaryColumns = List("reg_number", "city", "price", "description")
    val remainingColumns = processedDf.columns.filterNot(primaryColumns.contains).toList

    // save as a parquet
    processedDf
      .select((primaryColumns ++ remainingColumns).map(col): _*)
      .sort("city")
      .write
      .format("parquet")
      .mode("overwrite")
      .saveAsTable(targetTable)
  }

  private def buildCityExtractionLogic(addressCol: Column): Column = {
    // 1. Limpieza inicial: Convertimos a minúsculas y removemos el código postal inicial si viene pegado
    val cleanAddress = regexp_replace(
      regexp_replace(lower(addressCol), """^\d{6}\s*""", ""), // Quita "140155, " o "142432"
      """(?i)(?:обл\b|область\b|край\b|республика\b|респ\b|автодорога\b|ао\b|автономный\b|г\.о\.|округ\b|регион\b)""", 
      ""
    )

    // 2. Diccionario de prefijos de calles y palabras que DEBEMOS IGNORAR
    val prefixRegex = """(?i)\b(?:г\.|г\.\.|г|город|пгт\.|пгт|с\.|п\.|д\.|рп\.|рп|ст-ца\.|ст-ца|сл\.|сл|дп\.|дп|м\.|х\.|мкр\.|поселок|село|деревня|нас\.\s*пункт|нп\.)\s*([а-яА-Я0-9\-]+)"""
    val suffixRegex = """(?i)\b([а-яА-Я0-9\-]+)\s*(?:г|город|поселок|село)\b"""
    
    // 3. Jerarquía absoluta usando coalesce nativo
    initcap(
      trim(
        coalesce(
          // Bloque de seguridad absoluta para las 20 ciudades más grandes de Rusia
          when(lower(addressCol).contains("москва") || lower(addressCol).contains("зеленоград"), lit("Москва"))
            .when(lower(addressCol).contains("санкт-петербург") || lower(addressCol).contains("спб") , lit("Санкт-Петербург"))
            .when(lower(addressCol).contains("новосибирск"), lit("Новосибирск"))
            .when(lower(addressCol).contains("екатеринбург"), lit("Екатеринбург"))
            .when(lower(addressCol).contains("казань"), lit("Казань"))
            .when(lower(addressCol).contains("нижний новгород"), lit("Нижний Новгород"))
            .when(lower(addressCol).contains("красноярск"), lit("Красноярск"))
            .when(lower(addressCol).contains("челябинск"), lit("Челябинск"))
            .when(lower(addressCol).contains("самара"), lit("Самара"))
            .when(lower(addressCol).contains("уфа"), lit("Уфа"))
            .when(lower(addressCol).contains("ростов-на-дону"), lit("Ростов-на-Дону"))
            .when(lower(addressCol).contains("омск"), lit("Омск"))
            .when(lower(addressCol).contains("краснодар"), lit("Краснодар"))
            .when(lower(addressCol).contains("воронеж"), lit("Воронеж"))
            .when(lower(addressCol).contains("пермь"), lit("Пермь"))
            .when(lower(addressCol).contains("волгоград"), lit("Волгоград"))
            .when(lower(addressCol).contains("саратов"), lit("Саратов"))
            .when(lower(addressCol).contains("тюмень"), lit("Тюмень"))
            .when(lower(addressCol).contains("тольятти"), lit("Тольятти"))
            .when(lower(addressCol).contains("барнаул"), lit("Барнаул")),

          // Si existen banderas explícitas, las extraemos primero
          nullif(regexp_extract(addressCol, prefixRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, suffixRegex, 1), lit("")),

          // FALLBACK BRUTAL PARA CASOS DESNUDOS: 
          // Extrae la primera palabra real que queda tras remover códigos postales y provincias
          nullif(regexp_extract(cleanAddress, """(?i)\b([а-яёА-ЯЁ0-9\-]{4,})\b""", 1), lit("")),

          lit("EMPTY")
        )
      )
    )
  }
}
