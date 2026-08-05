import java.io.File
import scala.io.Source
import scala.tools.nsc.Settings
import scala.tools.nsc.interpreter.IMain
import scala.tools.nsc.interpreter.shell.ReplReporterImpl
import scala.tools.nsc.interpreter.shell.ReplReporterImpl.defaultOut

//noinspection ScalaWeakerAccess
object ScraperApp extends App {
  // basic checks
  if (args.length < 1) {
    println("Usage: java -jar mariposa-scraper.jar MyScript.scala")
    sys.exit(1)
  } else println("=== Mariposa Scala Script Runner 2===")

  // read user *.scala file
  val className = new File(args.head).getName.stripSuffix(".scala")
  val src = Source.fromFile(args.head)
  val scriptContent = try {src.mkString} finally {src.close()}

  // create interpreter
  val settings = new Settings()
  settings.usejavacp.value = true    // must have since Scala 2.8
  val interpreter = new IMain(settings, new ReplReporterImpl(settings, defaultOut))

  // compile & load user class
  println(s"Compiling: $className...")
  if (!interpreter.compileString(scriptContent))
    throw new RuntimeException(s"Compilation failed for class: $className")
  val jobClass = interpreter.classLoader.loadClass(className)
  val job = jobClass.getDeclaredConstructor().newInstance()
  val runMethod = jobClass.getMethod("run")

  // run user class
  println(s"Executing: $className.run()...")
  runMethod.invoke(job)
  println(s"SUCCESS: $className")
}

/*
Example:
import sttp.client3._
import org.jsoup.Jsoup

class YandexJob {
  def run(): Unit = {
    println("--- Hello YandeJob! ---")
    val http = HttpURLConnectionBackend()

    val response = basicRequest.get(uri"https://mc.yandex.ru/metrika/match.html").send(http)
    response.body match {
      case Right(html) =>
        val div = Jsoup.parse(html).select(".main").first()
        val yandexResponse = (
          div.select("h1").text(), div.select("h3").text(), div.select("p").text(), div.select("button").text()
        )
        println(s"Result: $yandexResponse")
      case Left(err) =>
        println(s"Failed: $err")
    }
  }
}
*/
