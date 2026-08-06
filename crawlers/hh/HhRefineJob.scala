// spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly mariposa-fly-*.jar HhRefineJob.scala &
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

class HhRefineJob {
  private val sourceTable = "hh.t_import"
  private val targetTable = "hh.refine"

  def run(spark: SparkSession): Unit = {
    import spark.implicits._
    println(s"[ETL]: $sourceTable -> $targetTable")

    spark
      .read.table(sourceTable)
      .filter($"vacancy_id".isNotNull && 
        $"name".isNotNull && trim($"name") =!= "" &&
        $"area_name".isNotNull && trim($"area_name") =!= ""
      )
      .dropDuplicates("vacancy_id")
      .sort("area_name")
      .write
      .format("parquet")
      .mode("overwrite")
      .saveAsTable(targetTable)
  }
}
