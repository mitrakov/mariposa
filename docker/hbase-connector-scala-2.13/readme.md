Original: https://github.com/apache/hbase-connectors/tree/master/spark
This repo was re-written to Scala 2.13, see binaries in "compiled" folder

Command:
```sh
mvn -Dspark.version=4.1.1 -Dscala.version=2.13.17 -Dhadoop-three.version=3.4.2 -Dscala.binary.version=2.13 -Dhbase.version=2.5.13 -DskipTests clean install
```
