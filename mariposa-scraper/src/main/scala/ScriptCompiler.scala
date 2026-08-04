import scala.tools.nsc.Settings
import scala.tools.nsc.interpreter.IMain
import scala.tools.nsc.interpreter.shell.ReplReporterImpl
import scala.tools.nsc.interpreter.shell.ReplReporterImpl.defaultOut
import scala.io.Source
import java.io.File
import java.util.function.Consumer
import sttp.client3.{SttpBackend, Identity}

object ScriptCompiler {

  // TODO: refine
  def compileAndRun(scriptPath: String, backend: SttpBackend[Identity, Any]): Unit = {
    val file = new File(scriptPath)
    val className = file.getName.stripSuffix(".scala")

    // 1. Leer el archivo del Data Scientist
    val src = Source.fromFile(scriptPath)
    val scriptContent = try src.mkString finally src.close()

    // 2. Configurar el Classpath ganador de Mariposa-Fly
    val driverJarPath = this.getClass.getProtectionDomain.getCodeSource.getLocation.getPath
    val existingClasspath = System.getProperty("java.class.path")

    val settings = new Settings()
    settings.usejavacp.value = true
    settings.classpath.value = s"$existingClasspath:$driverJarPath"

    // 3. Inicializar el Intérprete amarrado al ClassLoader actual
    val currentClassLoader = Thread.currentThread().getContextClassLoader
    val reporter = new ReplReporterImpl(settings, defaultOut)
    val interpreter = new IMain(settings, Some(currentClassLoader), settings, reporter)

    // 4. Compilar en caliente
    if (!interpreter.compileString(scriptContent)) {
      throw new RuntimeException(s"Compilation failed inside IMain for class: $className")
    }

    // 5. Cargar la clase e instanciarla como un Consumer estándar de Java
    val jobClass = interpreter.classLoader.loadClass(className)
    val instance = jobClass.getDeclaredConstructor().newInstance()

    // Evaluamos si el Data Scientist implementó correctamente el estándar
    instance match {
      case consumer: Consumer[SttpBackend[Identity, Any]] @unchecked =>
        // 💡 Ejecutamos el método estándar accept(T t) de la JDK
        consumer.accept(backend)
      case _ =>
        throw new IllegalArgumentException(s"La clase $className debe implementar java.util.function.Consumer[SttpBackend[Identity, Any]]")
    }
  }
}
