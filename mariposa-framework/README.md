# Mariposa project

## Usage as **Library**
### Sbt
```scala
// build.sbt
name := "datamartSbt"
version := "0.1.0"
scalaVersion := "2.13.17"
resolvers += Resolver.mavenLocal     // TODO: publish to artifactory
libraryDependencies += "com.mitrakoff" %% "mariposa" % "1.0.0"
assembly / mainClass := Some("Main")
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs*) =>
    xs match {
      case "services" :: _ => MergeStrategy.concat
      case _               => MergeStrategy.discard
    }
  case _ => MergeStrategy.first
}
```

```scala
// project/plugins.sbt
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.3.1")
```

```scala
// Main.scala
import com.mitrakoff.mariposa.Mariposa

object Main1 extends App {
  Mariposa.kafka2Hive
    .builder()
    .withKafkaTopic("my-topic")
    .withHiveTable("myTable")
    .build()
    .run()
}

object Main2 extends App {
  val catalog = s"""{
   "table":{"namespace":"default", "name":"sensor_data"},
     "rowkey":"key",
     "columns":{
     "rowkey":{"cf":"rowkey", "col":"key", "type":"string"},
     "metric":{"cf":"cf1", "col":"metric", "type":"string"},
     "value":{"cf":"cf1", "col":"value", "type":"string"}
     }
   }"""
  Mariposa.kafka2HBase
    .builder()
    .withKafkaTopic("my-topic")
    .withHBaseJsonCatalog(catalog)
    .build()
    .run()
}
```

Run:
```shell
spark-submit my.jar
```
