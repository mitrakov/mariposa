println(s"Hadoop Version: ${org.apache.hadoop.util.VersionInfo.getVersion}")
println(s"Hadoop Core JAR Location: ${classOf[org.apache.hadoop.conf.Configuration].getProtectionDomain.getCodeSource.getLocation}")
println(s"HADOOP_CONF_DIR: ${sys.env.getOrElse("HADOOP_CONF_DIR", "Not Set")}")