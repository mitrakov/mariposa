name := "mariposa-sou"
version := "1.0"
scalaVersion := "2.13.18"

val pekkoVersion = "2.0.0-M1"

libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-http"            % pekkoVersion,
  "org.apache.pekko" %% "pekko-stream"          % pekkoVersion,
  "org.apache.pekko" %% "pekko-actor-typed"     % pekkoVersion,
  "org.apache.pekko" %% "pekko-http-spray-json" % pekkoVersion,
)
