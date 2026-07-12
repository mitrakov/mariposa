import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

class MariposaTestJob {
 def run(spark: SparkSession): Unit = {
   import spark.implicits._
   spark.sql("CREATE TABLE IF NOT EXISTS default.mariposa_test_table (id INT, name STRING) STORED AS PARQUET")

   val newRows = Seq((1, "Alex"), (2, "Maria")).toDF("id", "name")
   newRows.write.mode("append").insertInto("default.mariposa_test_table")

   val rawDf = spark.read.table("default.mariposa_test_table")
   rawDf.show()

   spark.sql("DROP TABLE IF EXISTS default.mariposa_test_table")
 }
}
