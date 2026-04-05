package com.mitrakoff.mariposa

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.Trigger
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog

object Main {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("KafkaToHBase-Mariposa")
      .getOrCreate()

    // define the JSON schema coming from Kafka
    val jsonSchema = new StructType()
      .add("rowkey", StringType)
      .add("metric", StringType)
      .add("value", StringType)

    // HBase Catalog mapping
    val catalog = s"""{
                     |"table":{"namespace":"default", "name":"sensor_data"},
                     |"rowkey":"key",
                     |"columns":{
                     |"rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
                     |"metric":{"cf":"cf1", "col":"metric", "type":"string"},
                     |"value":{"cf":"cf1", "col":"value", "type":"string"}
                     |}
                     |}""".stripMargin

    // read from Kafka
    val kafkaDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "localhost:9092")
      .option("subscribe", "telemetry")
      .option("startingOffsets", "latest")
      .load()

    // parse JSON and filter out empty rowkeys
    val processedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as json_payload")
      .select(from_json(col("json_payload"), jsonSchema).as("data"))
      .select("data.*")
      .filter("rowkey IS NOT NULL AND rowkey != ''")

    // 2rite to HBase with a 5-second trigger
    val query = processedDF.writeStream
      .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
        if (!batchDF.isEmpty) {
          println(s"--- Writing Batch $batchId to HBase ---")
          batchDF.show()

          batchDF.write
            .options(Map(HBaseTableCatalog.tableCatalog -> catalog))
            .format("org.apache.hadoop.hbase.spark")
            .save()
        }
      }
      .trigger(Trigger.ProcessingTime("5 seconds"))
      .option("checkpointLocation", "/tmp/spark-checkpoints/mariposa")
      .start()

    query.awaitTermination()
  }
}

// hbase shell: create 'sensor_data', 'cf1'
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic telemetry
// kafka-console-producer.sh --bootstrap-server localhost:9092 --topic telemetry
// {"rowkey": "sensor_001", "metric": "temperature", "value": "24.5"}
