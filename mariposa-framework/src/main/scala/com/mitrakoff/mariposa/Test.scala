package com.mitrakoff.mariposa

import io.cucumber.core.cli.Main

// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-1
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-2
// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic-3
// spark.sql("""CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;""")
// spark-submit --class com.mitrakoff.mariposa.Test mariposa-assembly-1.0.0.jar
// test_catalog.json:
/*{
  "table":{"namespace":"default", "name":"sensor_data"},
  "rowkey":"key",
  "columns":{
    "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
    "metric":{"cf":"cf1", "col":"metric", "type":"string"},
    "value": {"cf":"cf1", "col":"value",  "type":"string"}
  }
}*/
object Test extends App {
  Main.run("classpath:features", "--glue", "com.mitrakoff.mariposa.steps")
}
