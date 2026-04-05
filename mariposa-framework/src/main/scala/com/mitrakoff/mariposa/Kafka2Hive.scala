package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.Trigger

object Kafka2Hive {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("KafkaToHive-Mariposa")
      .config("spark.sql.warehouse.dir", "/user/hive/warehouse")
      .config("hive.metastore.uris", "thrift://localhost:9083")
      .enableHiveSupport()
      .getOrCreate()

    val jsonSchema = new StructType()
      .add("rowkey", StringType)
      .add("metric", StringType)
      .add("value", StringType)

    val kafkaDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "localhost:9092")
      .option("subscribe", "telemetry")
      .option("startingOffsets", "earliest")
      .option("failOnDataLoss", "false")      // for stability
      .load()

    val processedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as json_payload")
      .select(from_json(col("json_payload"), jsonSchema).as("data"))
      .select("data.*")
      .filter("rowkey IS NOT NULL")

    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        if (!batchDF.isEmpty) {
          println(s"--- Committing Batch $batchId to Hive ---")
          batchDF.write.insertInto("telemetry_hive")
        }
      }
      .trigger(Trigger.ProcessingTime("5 seconds"))
      .option("checkpointLocation", "/tmp/spark-checkpoints/mariposa-hive")
      .start()

    query.awaitTermination()
  }
}


// spark.sql("""CREATE TABLE telemetry_hive (rowkey STRING, metric STRING, value STRING) USING HIVE;""")
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic telemetry
// spark-submit mariposa-framework-assembly-1.0.0.jar
// kafka-console-producer.sh --bootstrap-server localhost:9092 --topic telemetry
// {"rowkey": "sensor_002", "metric": "temperature", "value": "25.6"}
// spark.sql("SELECT * FROM telemetry_hive;").show(truncate = false)
