package com.mitrakoff.mariposa.fly

import org.apache.spark.sql.SparkSession
import scala.tools.nsc.interpreter.IMain
import scala.tools.nsc.Settings
import scala.tools.nsc.interpreter.shell.ReplReporterImpl
import scala.tools.nsc.interpreter.shell.ReplReporterImpl.defaultOut
import scala.io.Source
import java.io.File

object MariposaFly {
  def main(args: Array[String]): Unit = {
    if (args.length < 1) {
      println("Usage: spark-submit driver.jar <path-to-JobClassName.scala>")
      sys.exit(1)
    }

    val scriptFile = new File(args(0))
    if (!scriptFile.exists()) {
      println(s"Error: File not found at ${scriptFile.getAbsolutePath}")
      sys.exit(1)
    }

    val fileName = scriptFile.getName
    if (!fileName.endsWith(".scala")) {
      println(s"Error: Target file $fileName must have a .scala extension")
      sys.exit(1)
    }
    val className = fileName.stripSuffix(".scala")

    val spark = SparkSession.builder()
      .appName(s"Mariposa-Fly: $className")
      .enableHiveSupport()
      .getOrCreate()

    try {
      val src = Source.fromFile(scriptFile)
      val scriptContent = src.mkString
      src.close()

      val settings = new Settings()
      settings.usejavacp.value = true

      // Locate the physical path of the driver.jar housing MariposaJob
      val driverJarPath = this.getClass.getProtectionDomain.getCodeSource.getLocation.getPath
      val existingClasspath = System.getProperty("java.class.path")
      settings.classpath.value = s"$existingClasspath:$driverJarPath"

      // --- CRUCIAL CLASSLOADER FIX START ---
      // Get Spark's active classloader context
      val sparkClassLoader = Thread.currentThread().getContextClassLoader

      val reporter = new ReplReporterImpl(settings, defaultOut)

      // Explicitly pass Spark's classloader as the parent to the interpreter environment
      val interpreter = new IMain(
        settings,
        Some(sparkClassLoader), // Encapsulate in an Option
        settings,                // Pass settings a second time for compilerSettings
        reporter
      )
      // ---- CRUCIAL CLASSLOADER FIX END ----

      println(s"Compiling $className on-the-fly...")

      if (!interpreter.compileString(scriptContent)) {
        throw new RuntimeException(s"Compilation failed for code in: $fileName")
      }

      val classLoader = interpreter.classLoader
      val runtimeClass = classLoader.loadClass(className)

      // Now this cast will succeed flawlessly!
      val jobInstance = runtimeClass.getDeclaredConstructor().newInstance().asInstanceOf[MariposaJob]

      println(s"Executing runtime class: $className")
      jobInstance.run(spark)

      println(s"Job $className completed successfully!")

    } catch {
      case e: Exception =>
        e.printStackTrace()
        sys.exit(1)
    } finally {
      spark.stop()
    }
  }
}

trait MariposaJob { def run(spark: SparkSession): Unit }
