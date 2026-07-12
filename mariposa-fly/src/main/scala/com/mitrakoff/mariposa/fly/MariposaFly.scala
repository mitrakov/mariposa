package com.mitrakoff.mariposa.fly

import org.apache.spark.sql.SparkSession
import java.io.File
import scala.tools.nsc.interpreter.IMain
import scala.tools.nsc.Settings
import scala.tools.nsc.interpreter.shell.ReplReporterImpl
import scala.tools.nsc.interpreter.shell.ReplReporterImpl.defaultOut
import scala.io.Source

object MariposaFly extends App {
  // basic checks
  if (args.length < 1) {
    println("Usage: spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly mariposa-fly-assembly-1.0.0.jar MyJob.scala")
    sys.exit(1)
  }
  
  // create spark session
  val className = new File(args.head).getName.stripSuffix(".scala")
  val spark = SparkSession.builder().appName(s"Mariposa-Fly: $className").enableHiveSupport().getOrCreate()

  try {
    // read user *.scala file
    val src = Source.fromFile(args.head)
    val scriptContent = src.mkString
    src.close()

    // add spark classpath to interpreter settings
    val driverJarPath = this.getClass.getProtectionDomain.getCodeSource.getLocation.getPath
    val existingClasspath = sys.props("java.class.path")
    val settings = new Settings()
    settings.classpath.value = s"$existingClasspath:$driverJarPath"

    // create interpreter
    val sparkClassLoader = Thread.currentThread().getContextClassLoader
    val reporter = new ReplReporterImpl(settings, defaultOut)
    val interpreter = new IMain(settings, Some(sparkClassLoader), settings, reporter)

    // compile & load user class
    println(s"Compiling: $className...")
    if (!interpreter.compileString(scriptContent))
      throw new RuntimeException(s"Compilation failed for class: $className")
    val job = interpreter.classLoader.loadClass(className).getDeclaredConstructor().newInstance().asInstanceOf[MariposaJob]

    // run user class
    println(s"Executing: $className...")
    job.run(spark)
    println(s"SUCCESS: $className")
  } finally {
    spark.stop()
  }
}

trait MariposaJob { def run(spark: SparkSession): Unit }
