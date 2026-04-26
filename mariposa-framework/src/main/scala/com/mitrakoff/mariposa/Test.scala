package com.mitrakoff.mariposa

import io.cucumber.core.cli.Main

// kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic
// spark.sql("""CREATE TABLE test_table (rowkey STRING, metric STRING, value STRING) USING HIVE;""")
// spark-submit --class com.mitrakoff.mariposa.Test mariposa-assembly-1.0.0.jar
object Test extends App {
  Main.run("classpath:features", "--glue", "com.mitrakoff.mariposa.steps")
}
