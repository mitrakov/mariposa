import org.apache.hadoop.hbase.HBaseConfiguration
import org.apache.hadoop.hbase.spark.HBaseContext
import org.apache.hadoop.hbase.spark.datasources.HBaseTableCatalog

val catalog = s"""{
      |"table":{"namespace":"default", "name":"tommy_apps"},
      |"rowkey":"key",
      |"columns":{
        |"id":{"cf":"rowkey", "col":"key", "type":"string"},
        |"app_name":{"cf":"cf", "col":"name", "type":"string"},
        |"category":{"cf":"cf", "col":"type", "type":"string"}
      |}
    |}""".stripMargin
val tommyData = Seq(
      ("1", "Tommy Player", "Media"),
      ("2", "Tommylingo", "Language"),
      ("3", "Tommy Annals", "Diary"),
      ("4", "Tommypush", "Notification")
    )
val df = tommyData.toDF("id", "app_name", "category")
df.show()

val hbaseConf = HBaseConfiguration.create()
new HBaseContext(spark.sparkContext, hbaseConf)

df.write.options(Map(HBaseTableCatalog.tableCatalog -> catalog, HBaseTableCatalog.newTable -> "5")).format("org.apache.hadoop.hbase.spark").save()

val readDF = spark.read.options(Map(HBaseTableCatalog.tableCatalog -> catalog)).format("org.apache.hadoop.hbase.spark").load()
readDF.show()
