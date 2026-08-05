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
  } else println("=== Mariposa Scala Script Runner ===")

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
Example 1 (HtmlJob.scala):
import sttp.client3._
import org.jsoup.Jsoup

class HtmlJob {
  def run(): Unit = {
    println("--- Example parsing HTML: ---")
    val http = HttpURLConnectionBackend()
    val url = uri"https://mc.yandex.ru/metrika/match.html"

    println(s"Fetch $url")
    val response = basicRequest.get(url).send(http)
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

/*
Example 2 (JsonJob.scala):
import io.circe.generic.codec.DerivedAsObjectCodec.deriveCodec
import sttp.client3._
import sttp.client3.circe.asJson

class JsonJob {
  case class MambaResponse(title: String, description: String, keywords: String, metaRobots: String, header: String)
  def run(): Unit = {
    println("--- Example parsing JSON: ---")
    val http = HttpURLConnectionBackend()
    val url = uri"https://www.mamba.ru/api/seo/pages-meta?url=%2Fru"

    println(s"Fetch: $url")
    val response = basicRequest.get(url).response(asJson[MambaResponse]).send(http)
    response.body match {
      case Right(mamba) => println(s"Result: $mamba")
      case Left (error) => println(s"Error: $error")
    }
  }
}
*/

/*
Example 3 (XmlJob.scala):
import sttp.client3._
import scala.xml.XML

class XmlJob extends App {
  case class PomResponse(group: String, artifact: String, version: String, url: String)
  def run(): Unit = {
    println("--- Example parsing XML: ---")
    val http = HttpURLConnectionBackend()
    val url = uri"https://repo1.maven.org/maven2/org/scala-lang/scala-library/2.13.18/scala-library-2.13.18.pom"

    println(s"Fetch: $url")
    val response = basicRequest.get(url).response(asStringAlways map parsePom).send(http)
    response.body match {
      case Right(pom) => println(s"Result: $pom")
      case Left (err) => println(s"Error: $err")
    }
  }

  def parsePom(xmlString: String): Either[String, PomResponse] = try {
    val xml = XML.loadString(xmlString)
    Right(PomResponse((xml \\ "groupId").text, (xml \\ "artifactId").text, (xml \\ "version").text, (xml \\ "url").head.text))
  } catch { case e: Exception => Left(s"Failed to parse XML: ${e.getMessage}")}
}
 */