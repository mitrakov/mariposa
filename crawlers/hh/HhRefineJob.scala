// exec spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly mariposa-fly-*.jar HhRefineJob.scala
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types.IntegerType

class HhRefineJob {
  private val sourceTable = "hh.t_import"
  private val targetTable = "hh.refine"
  private val usdToRur = 92.0
  private val eurToRur = 100.0
  private val kztToRur = 0.20

  def run(spark: SparkSession): Unit = {
    import spark.implicits._
    println(s"[ETL]: $sourceTable -> $targetTable")

    spark.read
      .table(sourceTable)
      .filter($"vacancy_id".isNotNull &&
        $"name".isNotNull && trim($"name") =!= "" &&
        $"area_name".isNotNull && trim($"area_name") =!= ""
      )
      .dropDuplicates("vacancy_id")
      .withColumn("rur_from", {
        val curr = upper(coalesce($"currency", lit("RUR")))
        when(curr === "RUR" || curr === "RUB", $"salary_from")
          .when(curr === "USD", $"salary_from" * usdToRur)
          .when(curr === "EUR", $"salary_from" * eurToRur)
          .when(curr === "KZT", $"salary_from" * kztToRur)
          .otherwise($"salary_from")}
        )
      .withColumn("rur_to", {
        val curr = upper(coalesce($"currency", lit("RUR")))
        when(curr === "RUR" || curr === "RUB", $"salary_to")
          .when(curr === "USD", $"salary_to" * usdToRur)
          .when(curr === "EUR", $"salary_to" * eurToRur)
          .when(curr === "KZT", $"salary_to" * kztToRur)
          .otherwise($"salary_to")}
        )
      .withColumn("average_salary", round(
        when($"rur_from".isNotNull && $"rur_to".isNotNull, ($"rur_from" + $"rur_to") / 2.0)
          .when($"rur_from".isNotNull && $"rur_to".isNull,    $"rur_from" * 1.15)
          .when($"rur_from".isNull    && $"rur_to".isNotNull, $"rur_to" * 0.85)
          .otherwise(lit(null)), 0)
        .cast(IntegerType)
      )
      .sort("area_name")
      .write
      .format("parquet")
      .mode("overwrite")
      .saveAsTable(targetTable)
  }
}
