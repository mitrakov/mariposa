# add it to /opt/airflow/dags/spark_yarn_connection_test.py
import os
import glob
from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from datetime import datetime

# Helper to find the examples JAR dynamically
SPARK_HOME = os.getenv('SPARK_HOME', '/opt/spark')
JAR_PATTERN = f"{SPARK_HOME}/examples/jars/spark-examples_*.jar"
found_jars = glob.glob(JAR_PATTERN)
EXAMPLES_JAR = found_jars[0] if found_jars else "NOT_FOUND"

with DAG(dag_id='spark_yarn_connection_test') as dag:
    submit_job = SparkSubmitOperator(
        task_id='submit_spark_pi',
        application=EXAMPLES_JAR,
        java_class='org.apache.spark.examples.SparkPi',
        application_args=['10'], # Increased to 10 so it stays in YARN UI longer
        conf={
            "spark.master": "yarn",
            "spark.submit.deployMode": "client",
            "spark.executor.memory": "512m",
            "spark.driver.memory": "512m"
        },
        name='airflow-spark-test-pi'
    )
