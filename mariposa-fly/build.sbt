organization := "com.mitrakoff"
name := "mariposa-fly"
version := "1.0.0"
scalaVersion := "2.13.17" // matches Spark 4.1.1

libraryDependencies ++= Seq(
  "org.scala-lang" % "scala-compiler" % scalaVersion.value,
  "org.apache.spark" %% "spark-sql"  % "4.1.1" % "provided",
)
