version := "1.0.0"
scalaVersion := "2.13.17" // match Spark 4.1.1

val sparkVersion = "4.1.1"

lazy val root = (project in file("."))
  .settings(
    name := "mariposa-framework",
    resolvers += Resolver.mavenLocal,
    libraryDependencies ++= Seq(
      "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
      "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
      "org.apache.hadoop" % "hadoop-client" % "3.4.1" % "provided", // Cluster has this
      "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion, // Keep this (Spark doesn't ship with Kafka)
      ("org.apache.hbase.connectors.spark" % "hbase-spark" % "1.1.0").exclude("org.glassfish", "javax.el"),
      "org.apache.hbase.connectors.spark" % "hbase-spark-protocol-shaded" % "1.1.0",
    ),
    assembly / mainClass := Some("com.mitrakoff.mariposa.Kafka2Hive"),
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", xs*) =>
        xs match {
          case "MANIFEST.MF" :: Nil => MergeStrategy.discard
          case "services" :: _      => MergeStrategy.concat
          case _                    => MergeStrategy.discard
        }
      case "reference.conf" => MergeStrategy.concat
      case x if x.endsWith(".proto") => MergeStrategy.rename
      case x if x.contains("org/apache/hadoop/http") => MergeStrategy.first
      case x if x.contains("javax/servlet") => MergeStrategy.first
      case x if x.contains("javax/ws/rs") => MergeStrategy.first
      case x if x.contains("javax/inject") => MergeStrategy.first
      case x if x.contains("org/apache/hbase/thirdparty") => MergeStrategy.first
      case _ => MergeStrategy.first
    },
  )
