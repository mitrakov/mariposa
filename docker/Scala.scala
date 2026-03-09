println(s"Hadoop Version: ${org.apache.hadoop.util.VersionInfo.getVersion}")
println(s"Hadoop Core JAR Location: ${classOf[org.apache.hadoop.conf.Configuration].getProtectionDomain.getCodeSource.getLocation}")

spark.conf.get("spark.sql.catalogImplementation")    // hive
spark.sql("SHOW DATABASES").show()                   // default
spark.catalog.listDatabases().show(truncate=false)   // |default|spark_catalog|Default Hive database|hdfs://localhost:9000/user/hive/warehouse|

spark.sql("CREATE TABLE hive_test (id INT, message STRING) USING hive")
spark.sql("INSERT INTO hive_test VALUES (1, 'Tommy')")
spark.sql("SELECT * FROM hive_test").show()
