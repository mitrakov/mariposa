name := "mariposa-scraper"
version := "1.0"
scalaVersion := "2.13.18"
libraryDependencies ++= Seq(
  "org.scala-lang" % "scala-compiler" % scalaVersion.value, // compiler
  "org.scala-lang.modules" %% "scala-xml" % "2.4.0",        // xml parser
  "com.softwaremill.sttp.client3" %% "circe" % "3.11.0", // http client
  "io.circe" %% "circe-generic" % "0.14.10",             // json parser, v. should match "sttp.client3.circe" internal dependency
  "org.jsoup" % "jsoup" % "1.23.1",                      // html parser
  "org.apache.kafka" % "kafka-clients" % "4.2.0",        // kafka client, should match cluster version
)
