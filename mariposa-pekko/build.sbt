name := "mariposa-pekko"
version := "1.0"
scalaVersion := "2.13.18"

val pekkoVersion = "2.0.0-M1"
val hbaseVersion = "2.5.14"

libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-http"            % pekkoVersion,
  "org.apache.pekko" %% "pekko-stream"          % pekkoVersion,
  "org.apache.pekko" %% "pekko-actor-typed"     % pekkoVersion,
  "org.apache.pekko" %% "pekko-http-spray-json" % pekkoVersion,
  "org.apache.hbase" % "hbase-client"           % hbaseVersion,
  "org.apache.hbase" % "hbase-common"           % hbaseVersion,
  "ch.qos.logback"   % "logback-classic"        % "1.5.38"
)

assembly / assemblyMergeStrategy := {
  case "reference.conf" => MergeStrategy.concat // concat all reference.conf files so Pekko can read its settings
  case PathList("META-INF", xs @ _*) =>
    xs match {
      case "MANIFEST.MF" :: Nil => MergeStrategy.discard
      case _ => MergeStrategy.first
    }
  case _ => MergeStrategy.first
}

assembly / packageOptions += Package.ManifestAttributes("Add-Opens" -> "java.base/java.nio") // shitty Java-17
