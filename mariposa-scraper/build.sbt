name := "mariposa-scraper"
version := "1.0"
scalaVersion := "2.13.18"

val sttpVersion = "3.11.0"
val circeVersion = "0.14.16"

libraryDependencies ++= Seq(
  "org.scala-lang" % "scala-compiler" % scalaVersion.value,

// HTTP Client
  "com.softwaremill.sttp.client3" %% "core" % sttpVersion,
  "com.softwaremill.sttp.client3" %% "circe" % sttpVersion,

  // JSON Parsing (Circe)
  "io.circe" %% "circe-core" % circeVersion,
  "io.circe" %% "circe-generic" % circeVersion,
  "io.circe" %% "circe-parser" % circeVersion,

  // HTML Parsing (jsoup)
  "org.jsoup" % "jsoup" % "1.23.1",

  // Kafka Client
  "org.apache.kafka" % "kafka-clients" % "4.3.1",

  // Logging
  "org.slf4j" % "slf4j-api" % "2.0.18",
  "ch.qos.logback" % "logback-classic" % "1.6.1" % Runtime
)

assembly / assemblyMergeStrategy := {
  case "module-info.class" => MergeStrategy.discard
  case x if x.endsWith("module-info.class") => MergeStrategy.discard
  case x =>
    val oldStrategy = (assembly / assemblyMergeStrategy).value
    oldStrategy(x)
}
