name := "mariposa-scraper"
version := "1.0"
scalaVersion := "2.13.18"

val sttpVersion = "3.11.0"
val circeVersion = "0.14.16"

libraryDependencies ++= Seq(
  // Runtime Compiler
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
)
