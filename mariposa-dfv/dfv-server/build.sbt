name := "dfv-server"
version := "1.0"
scalaVersion := "2.13.18"

val PekkoVersion = "1.0.2"
val CirceVersion = "0.14.6"

libraryDependencies ++= Seq(
  // Apache Pekko HTTP
  "org.apache.pekko" %% "pekko-http" % "1.0.1",
  "org.apache.pekko" %% "pekko-actor-typed" % PekkoVersion,
  "org.apache.pekko" %% "pekko-stream" % PekkoVersion,

  // Apache HBase Client
  "org.apache.hbase" % "hbase-client" % "2.5.5",
  "org.apache.hbase" % "hbase-common" % "2.5.5",

  // Circe para JSON (Ligero y funcional)
  "io.circe" %% "circe-core" % CirceVersion,
  "io.circe" %% "circe-generic" % CirceVersion,
  "io.circe" %% "circe-parser" % CirceVersion,
  "com.github.pjfanning" %% "pekko-http-circe" % "2.8.0"
)

assembly / assemblyMergeStrategy := {
  case PathList("META-INF", "services", xs*) => MergeStrategy.filterDistinctLines     // for Java SPI
  case PathList("META-INF", xs*) => MergeStrategy.discard                             // discard multiple manifests
  case x if x.endsWith(".conf")  => MergeStrategy.concat                              // for application.conf, reference.conf, etc.
  case _ => MergeStrategy.first
}
