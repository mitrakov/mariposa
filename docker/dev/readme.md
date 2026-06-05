## Spark
```scala
spark.sql("CREATE TABLE hello_world (id INT, data STRING) USING hive")
spark.sql("INSERT INTO hello_world VALUES (1, 'It is working')")
spark.sql("SELECT * FROM hello_world").show()
```
