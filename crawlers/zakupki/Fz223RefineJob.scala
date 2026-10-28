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
    // 1. Definición de las expresiones regulares nativas
    val prefixRegex = """(?i)\b(?:г\.|г\.\.|г|город)\s*([а-яА-Я0-9\-]+)"""
    val suffixRegex = """(?i)\b([а-яА-Я0-9\-]+)\s*(?:г|город)\b"""
    val ruralRegex  = """(?i)\b(?:с\.|п\.|д\.|рп|село|поселок|деревня)\s*([а-яА-Я0-9\-]+)"""
    val commaFallbackRegex = """^[^,]+,\s*([а-яА-Я0-9\-]+)\s*,"""

    // 2. Construcción de la jerarquía lúdica con Coalesce
    initcap(
      trim(
        coalesce(
          // Red de seguridad absoluta para megapólis y casos especiales
          when(lower(addressCol).contains("санкт-петербург") || lower(addressCol).contains("спб"), lit("Санкт-Петербург"))
            .when(lower(addressCol).contains("москва"), lit("Москва"))
            .when(lower(addressCol).contains("севастополь"), lit("Севастополь"))
            .when(lower(addressCol).startsWith("ростов-на-дону"), lit("Ростов-на-Дону")),

          // Evaluación secuencial de patrones (nullif convierte "" en NULL para que coalesce continúe)
          nullif(regexp_extract(addressCol, prefixRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, suffixRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, ruralRegex, 1), lit("")),
          nullif(regexp_extract(addressCol, commaFallbackRegex, 1), lit("")),

          lit("Unknown")
        )
      )
    )
  }
}
