import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

class SimpleSqlValidatorSpec extends AnyFunSuite with Matchers {
  test("Debería aceptar consultas Spark SQL perfectamente válidas") {
    val sql1 = "SELECT * FROM default.my_table"
    val sql2 = "WITH tmp AS (SELECT id, name FROM users) SELECT * FROM tmp WHERE id > 10"
    val sql3 = "SELECT id, count(1) FROM logs GROUP BY id HAVING count(1) > 5"

    SimpleSqlValidator.validate(sql1) shouldBe Right(true)
    SimpleSqlValidator.validate(sql2) shouldBe Right(true)
    SimpleSqlValidator.validate(sql3) shouldBe Right(true)
  }

  test("Debería tolerar paréntesis dentro de strings literales sin romper el balanceo (Robustez)") {
    // El paréntesis dentro del string 'Ingeniero (Sistemas)' no debe contar como un token de control
    val sql = "SELECT * FROM employees WHERE puesto = 'Ingeniero (Sistemas)' AND salario > 2000"
    SimpleSqlValidator.validate(sql) shouldBe Right(true)
  }

  test("Debería rechazar consultas vacías o nulas") {
    SimpleSqlValidator.validate("") shouldBe Left("La consulta SQL está vacía.")
    SimpleSqlValidator.validate("   ") shouldBe Left("La consulta SQL está vacía.")
  }

  test("Debería rechazar si no inicia con SELECT o WITH") {
    val sql = "DROP TABLE my_table"
    SimpleSqlValidator.validate(sql) shouldBe (a[Left[_, _]])
  }

  test("Debería rechazar si le falta la cláusula FROM") {
    val sql = "SELECT id, name, age"
    SimpleSqlValidator.validate(sql) shouldBe(a[Left[_, _]])
  }

  test("Debería atrapar paréntesis abiertos sin cerrar") {
    val sql = "SELECT id, name FROM users WHERE id IN (1, 2, 3"
    SimpleSqlValidator.validate(sql) shouldBe Left("Error de sintaxis: Paréntesis desbalanceados. Quedaron 1 paréntesis abiertos sin cerrar.")
  }

  test("Debería atrapar paréntesis de cierre huérfanos") {
    val sql = "SELECT id FROM (SELECT id FROM users))"
    SimpleSqlValidator.validate(sql) shouldBe Left("Error de sintaxis: Paréntesis de cierre ')' huérfano detectado antes de su apertura.")

    val sqlHuérfano = "SELECT id FROM users) WHERE id = 1"
    SimpleSqlValidator.validate(sqlHuérfano) shouldBe Left("Error de sintaxis: Paréntesis de cierre ')' huérfano detectado antes de su apertura.")
  }

  test("Debería atrapar comas asesinas justo antes del FROM") {
    val sql = "SELECT id, name, age, FROM users"
    SimpleSqlValidator.validate(sql) shouldBe Left("Error de sintaxis: Se detectó una coma ',' huérfana justo antes de la cláusula FROM.")
  }
}
