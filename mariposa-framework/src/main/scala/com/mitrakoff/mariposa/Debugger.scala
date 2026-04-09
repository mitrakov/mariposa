package com.mitrakoff.mariposa

object Debugger extends App {
  val catalog = s"""{
   "table":{"namespace":"default", "name":"sensor_data"},
     "rowkey":"key",
     "columns":{
     "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
     "metric":{"cf":"cf1", "col":"metric", "type":"string"},
     "value":{"cf":"cf1", "col":"value", "type":"string"}
     }
   }"""
//  Mariposa.kafka2HBase
//    .builder()
//    .withHBaseJsonCatalog(catalog)
//    .withKafkaTopic("trix-topic")
//    .build()
//    .run()
  Mariposa.kafka2Hive
    .builder()
    .withHiveTable("students")
    .withKafkaTopic("tommy-topic")
    .build()
    .run()
}
