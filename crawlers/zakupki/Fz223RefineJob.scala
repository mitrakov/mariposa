import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._


// build.sbt: "org.apache.spark" %% "spark-sql"  % "4.1.1" % "provided"
// spark-submit --num-executors 5 --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar Fz223RefineJob.scala
class Fz223RefineJob {
  private val sourceTable = "zakupki.fz223_import"
  private val targetTable = "zakupki.fz223_refine"
  private val cityRegex = """(?i)\b(?:г\.|г\.\.|город)\s*([^,.\s]+)"""

  def run(spark: SparkSession): Unit = {
    import spark.implicits._
    println(s"[ETL]: $sourceTable -> $targetTable")

    // primary processing: remove duplicates, extract "city"
    val processedDf = spark.read.table(sourceTable)
      .filter($"reg_number".isNotNull && trim($"reg_number") =!= "")
      .dropDuplicates("reg_number")
      .withColumn("city", 
        initcap( // lowercase (e.g., ЕКАТЕРИНБУРГ -> Екатеринбург)
          coalesce(
            regexp_extract($"location", cityRegex, 1),
            regexp_extract($"address", cityRegex, 1),
            lit("EMPTY")
          )
        )
      )

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
}
