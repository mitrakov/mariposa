package com.mitrakoff.mariposa.steps

import com.mitrakoff.mariposa.Mariposa
import io.cucumber.datatable.DataTable
import io.cucumber.scala.{EN, ScalaDsl}
import org.apache.spark.sql.SparkSession

class MariposaSteps extends ScalaDsl with EN {
  Given("""a message from Kafka topic {string}:""") { (topic: String, dataTable: DataTable) =>
    // Write code here that turns the phrase above into concrete actions
  }

  When("""an UPLOAD command is executed in MariposaSQL:""") { (sql: String) =>
    // Aquí llamamos a tu lógica real del framework
    // El archivo SQL debe estar disponible en el clúster (o en HDFS)
    Mariposa.runMariposaSql(sql)
  }

  Then("""Hive table {string} should contain:""") { (tableName: String, dataTable: DataTable) =>
    val spark = SparkSession.builder().enableHiveSupport().getOrCreate()
    val count = spark.sql(s"SELECT count(*) FROM $tableName").collect()(0).getLong(0)
    assert(count > 0)
  }
}
