name := "mariposa-pekko"
version := "1.0"
scalaVersion := "2.13.18"

val pekkoVersion = "2.0.0-M1"
val hbaseVersion = "2.5.14"

libraryDependencies ++= Seq(
  // Pekko HTTP & Streams
  "org.apache.pekko" %% "pekko-http"            % pekkoVersion,
  "org.apache.pekko" %% "pekko-stream"          % pekkoVersion,
  "org.apache.pekko" %% "pekko-actor-typed"     % pekkoVersion,
  
  // HBase Client (Matches your 2.5.14 cluster)
  "org.apache.hbase" % "hbase-client"           % hbaseVersion,
  "org.apache.hbase" % "hbase-common"           % hbaseVersion,
  
  // Logging (Crucial for Hadoop/HBase libraries)
  "ch.qos.logback"   % "logback-classic"        % "1.5.38"
)

// Assembly strategy to fix merge conflicts between Hadoop/HBase and Pekko jars
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) =>
    xs match {
      case "MANIFEST.MF" :: Nil => MergeStrategy.discard
      case _ => MergeStrategy.first
    }
  case _ => MergeStrategy.first
}
