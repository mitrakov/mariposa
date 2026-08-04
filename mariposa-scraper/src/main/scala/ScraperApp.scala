import org.slf4j.LoggerFactory
import sttp.client3.HttpURLConnectionBackend

object ScraperApp {
  private val logger = LoggerFactory.getLogger(getClass)

  def main(args: Array[String]): Unit = {
    logger.info("=== Mariposa Pure Execution Engine ===")

    if (args.length < 1) {
      logger.error("Usage: java -jar mariposa-scraper.jar <script.scala>")
      sys.exit(1)
    }

    val scriptPath = args(0)
    val backend = HttpURLConnectionBackend()

    try {
      logger.info(s"Compiling and executing: $scriptPath")
      ScriptCompiler.compileAndRun(scriptPath, backend)
      logger.info("Execution finished successfully.")
    } catch {
      case e: Exception =>
        logger.error(s"Runtime error executing $scriptPath", e)
    } finally {
      backend.close()
    }
  }
}

/*
Example:
import java.util.function.Consumer
import sttp.client3._
import org.jsoup.Jsoup

class YandexJob extends Consumer[SttpBackend[Identity, Any]] {
  override def accept(backend: SttpBackend[Identity, Any]): Unit = {
    println("--- Start Example Script ---")

    val response = basicRequest.get(uri"https://mc.yandex.ru/metrika/match.html").send(backend)
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
