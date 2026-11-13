name := "mariposa-pekkodb"
scalaVersion := "3.3.9"
version := "1.0"

val pekkoVersion = "2.0.0"

libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-http"            % pekkoVersion,  // http-server
  "org.apache.pekko" %% "pekko-stream"          % pekkoVersion,  // must be in classpath
  "org.apache.pekko" %% "pekko-actor-typed"     % pekkoVersion,  // actor-system
  "org.apache.pekko" %% "pekko-http-spray-json" % pekkoVersion,  // json
  "ch.qos.logback"    % "logback-classic"       % "1.6.6",       // slf4j impl
  "org.xerial"        % "sqlite-jdbc"           % "3.54.1.0",    // sqlite jdbc driver
)

assemblyMergeStrategy := {
  case PathList("META-INF", "versions", "9", "module-info.class") => MergeStrategy.discard
  case "module-info.class"                                        => MergeStrategy.discard
  case x                                                          => MergeStrategy.defaultMergeStrategy(x)
}
