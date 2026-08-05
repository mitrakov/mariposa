name := "mariposa-scraper"
version := "1.0"
scalaVersion := "2.13.18"
libraryDependencies ++= Seq(
  "org.scala-lang" % "scala-compiler" % scalaVersion.value,
  "com.softwaremill.sttp.client3" %% "circe" % "3.11.0", // http client
  "io.circe" %% "circe-generic" % "0.14.10",             // version should match "sttp.client3.circe" internal dependency
  "org.jsoup" % "jsoup" % "1.23.1",                      // html parser
  "org.apache.kafka" % "kafka-clients" % "4.2.0",        // should match cluster version
)
