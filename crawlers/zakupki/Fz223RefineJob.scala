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
    // 1. Regex estándar para ciudades convencionales
    val prefixRegex = """(?i)\b(?:г\.|г\.\.|г|город)\s*([а-яА-Я0-9\-]+)"""
    val suffixRegex = """(?i)\b([а-яА-Я0-9\-]+)\s*(?:г|город)\b"""
    
    // 2. REGEX MEJORADO: Captura TODAS las variantes de asentamientos rusos que encontramos en tus datos
    // Mapea: рп. (рабочий поселок), пгт., с. (село), п. (поселок), д. (деревня), ст-ца. (станица), 
    // сл. (слобода), дп. (дачный поселок), м. (местечко), х. (хутор), мкр. (микрорайон)
    val ruralRegex = """(?i)\b(?:с\.|п\.|д\.|рп\.|рп|пгт\.|пгт|ст-ца\.|ст-ца|сл\.|сл|дп\.|дп|м\.|х\.|мкр\.|поселок|село|деревня|мч|местечко|р\.пос\.)\s*([а-яА-Я0-9\s\-]+?)(?=,|\d|\b)"""

    // 3. Estrategia jerárquica con Coalesce nativo
    initcap(
      trim(
        coalesce(
          when(lower(addressCol).contains("санкт-петербург") || lower(addressCol).contains("спб"), lit("Санкт-Петербург"))
            .when(lower(addressCol).contains("москва"), lit("Москва"))
            .when(lower(addressCol).contains("севастополь"), lit("Севастополь"))
            .when(lower(addressCol).contains("сириус"), lit("Сириус")) // Caso especial: Territorio Federal Сириус
            .when(lower(addressCol).startsWith("ростов-на-дону"), lit("Ростов-на-Дону")),

          // Evaluación secuencial de patrones de texto estructurado
          nullif(regexp_extract(addressCol, prefixRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, suffixRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, ruralRegex, 1), lit("")),

          lit("EMPTY")
        )
      )
    )
  }
}
