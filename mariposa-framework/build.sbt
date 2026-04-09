organization := "com.mitrakoff"
name := "mariposa"
version := "1.0.0"
scalaVersion := "2.13.17" // matches Spark 4.1.1

val sparkVersion = "4.1.1"

resolvers += Resolver.mavenLocal // TODO move to repo
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
  "org.apache.hadoop" % "hadoop-client" % "3.4.3" % "provided", // Cluster has this
  "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion, // Keep this (Spark doesn't ship with Kafka)
  ("org.apache.hbase.connectors.spark" % "hbase-spark" % "1.1.0").exclude("org.glassfish", "javax.el"),
  "org.apache.hbase.connectors.spark" % "hbase-spark-protocol-shaded" % "1.1.0",
)
assembly / mainClass := Some("com.mitrakoff.mariposa.Mariposa")
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs*) =>
    xs match {
      case "services" :: _ => MergeStrategy.concat
      case _               => MergeStrategy.discard
    }
  case _ => MergeStrategy.first
}
