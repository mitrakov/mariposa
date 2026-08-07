import scala.annotation.tailrec

object SimpleSqlValidator {
  /**
   * Valida sintaxis básica de Spark SQL de forma conservadora.
   * Devuelve Left(mensaje) solo si el error es 100% real.
   * Devuelve Right(true) si es válido o si es demasiado complejo para evaluar.
   */
  def validate(sql: String): Either[String, Unit] = {
    if (sql == null || sql.trim.isEmpty) {
      return Left("La consulta SQL está vacía.")
    }

    val cleanSql = sql.trim.replaceAll("\\s+", " ")
    val upperSql = cleanSql.toUpperCase

    // 1. Validar inicio obligatorio (Consultas de lectura permitidas en Mariposa)
    if (!upperSql.startsWith("SELECT") && !upperSql.startsWith("WITH")) {
      return Left("Sintaxis inválida: La consulta debe iniciar con SELECT o un bloque WITH.")
    }

    // 2. Validar existencia de la cláusula FROM (tolerando subconsultas o funciones)
    if (!upperSql.contains("FROM")) {
      return Left("Sintaxis inválida: No se encontró la cláusula obligatoria 'FROM'.")
    }

    // 3. Balanceo robusto de paréntesis ignorando lo que esté dentro de comillas (Strings literales)
    // Esto evita falsos positivos si el usuario escribe un String que contiene un paréntesis: ej. WHERE name = 'John (Jack)'
    val cleanTextWithoutStrings = removeSqlStringLiterals(sql)

    val balanceCheck = checkParenthesisBalance(cleanTextWithoutStrings)
    if (balanceCheck.isLeft) return balanceCheck

    // 4. Errores tipográficos letales y obvios
    // Coma huérfana antes del FROM (ej: SELECT a, b, FROM tabla)
    if (cleanSql.replaceAll("(?i)\\s+FROM", " FROM").contains(", FROM")) {
      return Left("Error de sintaxis: Se detectó una coma ',' huérfana justo antes de la cláusula FROM.")
    }

    Right()
  }

  /**
   * Remueve de forma segura los literales de string ('...' o "...") del SQL 
   * para evitar evaluar paréntesis o caracteres especiales dentro del texto.
   */
  private def removeSqlStringLiterals(sql: String): String = {
    // Expresión regular que empareja strings con comillas simples o dobles tolerando escapes
    sql.replaceAll("'([^'\\\\]|\\\\.)*'", "''")
      .replaceAll("\"([^\"\\\\]|\\\\.)*\"", "\"\"")
  }

  /**
   * Recorre el texto limpio sumando y restando paréntesis de forma segura.
   */
  private def checkParenthesisBalance(text: String): Either[String, Unit] = {
    @tailrec
    def loop(chars: List[Char], openCount: Int): Int = {
      if (openCount < 0) -1 // Se cerró un paréntesis antes de abrirse
      else chars match {
        case Nil => openCount
        case '(' :: tail => loop(tail, openCount + 1)
        case ')' :: tail => loop(tail, openCount - 1)
        case _ :: tail   => loop(tail, openCount)
      }
    }

    val finalCount = loop(text.toList, 0)

    if (finalCount == -1) Left("Error de sintaxis: Paréntesis de cierre ')' huérfano detectado antes de su apertura.")
    else if (finalCount > 0) Left(s"Error de sintaxis: Paréntesis desbalanceados. Quedaron $finalCount paréntesis abiertos sin cerrar.")
    else Right()
  }
}
