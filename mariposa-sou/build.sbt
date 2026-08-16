name := "mariposa-sou"
version := "1.0"
scalaVersion := "2.13.18"

val pekkoVersion = "2.0.0-M1"

libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-http"            % pekkoVersion,
  "org.apache.pekko" %% "pekko-stream"          % pekkoVersion,
  "org.apache.pekko" %% "pekko-actor-typed"     % pekkoVersion,
  "org.apache.pekko" %% "pekko-http-spray-json" % pekkoVersion,
  "ch.qos.logback"   % "logback-classic"        % "1.6.1",
)

assembly / assemblyMergeStrategy := {
  // Concatena configuraciones de Pekko
  case "reference.conf" => MergeStrategy.concat

  // 🔥 CORRECCIÓN PARA LOGBACK Y JAVA 17: Manejo de module-info.class duplicados
  case "module-info.class" => MergeStrategy.discard
  case PathList("META-INF", "versions", "module-info.class") => MergeStrategy.discard

  // Concatenar archivos de servicios de Hadoop/Spark/Pekko
  case PathList("META-INF", "services", _*) => MergeStrategy.concat

  // Limpieza de manifiestos y firmas del JAR
  case PathList("META-INF", xs @ _*) =>
    xs match {
      case "MANIFEST.MF" :: Nil => MergeStrategy.discard
      case x if x.endsWith(".SF") || x.endsWith(".DSA") || x.endsWith(".RSA") => MergeStrategy.discard
      case _ => MergeStrategy.first
    }

  // Estrategia por defecto para lo demás
  case _ => MergeStrategy.first
}
