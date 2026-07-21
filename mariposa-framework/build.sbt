organization := "com.mitrakoff"
name := "mariposa"
version := "1.0.1"
scalaVersion := "2.13.17" // matches Spark 4.1.1

val sparkVersion = "4.1.3"

resolvers += Resolver.mavenLocal // TODO move to repo
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion,
  "org.apache.hadoop" % "hadoop-client" % "3.4.3" % "provided", // 3.5.0 doesn't work, check why later
  "org.antlr" % "antlr4-runtime" % "4.13.1" % "provided",     // matches Spark 4.1.1
  "io.cucumber" %% "cucumber-scala" % "8.36.0",               // v8.37 requires Scala 2.13.18+
  "org.scalatest" %% "scalatest" % "3.2.20" % Test,
)

// Antlr4 plugin
Antlr4 / antlr4PackageName := Some("com.mitrakoff.mariposa")
Antlr4 / antlr4Version := "4.13.1"                            // matches Spark 4.1.1
enablePlugins(Antlr4Plugin)

// assembly plugin
assembly / mainClass := Some("com.mitrakoff.mariposa.Mariposa")
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs*) =>
    xs match {
      case "services" :: _ => MergeStrategy.concat
      case _               => MergeStrategy.discard
    }
  case _ => MergeStrategy.first
}

// 1.0.1: fix bug: https://github.com/apache/spark/pull/56526
