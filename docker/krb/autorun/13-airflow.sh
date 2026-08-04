#!/usr/bin/env bash
# Apache Airflow
set -euo pipefail
source utils.sh
source .env

check_env "IS_MASTER"


if [[ "$IS_MASTER" == "true" ]]; then
    if [[ ${SKIP_AIRFLOW:-} != "true" ]]; then
        check_env "MASTER_HOST"
        check_env "AIRFLOW_HOME"
        check_env "KEYTABS_DIR"
        check_env "AIRFLOW_DB_PASSWORD"

        cat <<EOF > $AIRFLOW_HOME/dags/spark_connection_test.py
import os
import glob
from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

# find the Spark examples JAR dynamically
SPARK_HOME = os.getenv('SPARK_HOME', '/opt/spark')
JAR_PATTERN = f"{SPARK_HOME}/examples/jars/spark-examples_*.jar"
found_jars = glob.glob(JAR_PATTERN)
EXAMPLES_JAR = found_jars[0] if found_jars else "NOT_FOUND"

MASTER_HOST = os.getenv('MASTER_HOST', '$MASTER_HOST')
KEYTABS_DIR = os.getenv('KEYTABS_DIR', '$KEYTABS_DIR')

with DAG(dag_id='spark_connection_test') as dag:
    submit_job = SparkSubmitOperator(
        task_id='submit_spark_pi',
        application=EXAMPLES_JAR,
        java_class='org.apache.spark.examples.SparkPi',
        application_args=['10'],
        principal=f'hadoop/{MASTER_HOST}@MARIPOSA.COM',
        keytab=f"{KEYTABS_DIR}/{MASTER_HOST}.keytab",
        name='airflow-spark-test-pi'
    )
EOF

        log "Starting Apache Airflow..."

        AIRFLOW_PASSWORD=$(vault kv get -field=admin secret/hadoop/airflow)
        check_env "AIRFLOW_PASSWORD"

        export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://airflow:$AIRFLOW_DB_PASSWORD@localhost:5432/airflow_db"
        export AIRFLOW__API__PORT=8085                                  # port 8080 is taken by Spark
        export AIRFLOW__API__BASE_URL=http://localhost:8085             # used by DAG executor
        export AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_USERS="admin:admin,tommy:user"
        export AIRFLOW__API__EXPOSE_CONFIG="True"                       # show configs in "Admin -> Config" tab

        echo "{\"admin\":\"$AIRFLOW_PASSWORD\", \"tommy\":\"tommy\"}" > "$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated"

        if [ ! -f "$AIRFLOW_HOME/airflow.cfg" ]; then
            log "First time run. Initializing Airflow database..."
            airflow db migrate
            info "Airflow database initialized"
        else
            info "OK: Airflow database already initialized"
        fi

        log "Starting Apache Airflow components..."
        airflow api-server --port 8085 > "$AIRFLOW_HOME/logs/airflow-api-server.log" 2>&1 &

        # update secret key before running scheduler and dag-processor, so that they can pick up a new value
        # for some reason AIRFLOW__API__SECRET_KEY doesn't work => sed manually
        until [ -s "$AIRFLOW_HOME/airflow.cfg" ]; do sleep 1; done
        grep 'secret_key = ' $AIRFLOW_HOME/airflow.cfg
        sed -i 's/^secret_key = .*$/secret_key = d80678ac0f4fa9e278aa83e1fc72001c2ad91f1da8c77f6c7ca914a8095be758/g' $AIRFLOW_HOME/airflow.cfg
        grep 'secret_key = ' $AIRFLOW_HOME/airflow.cfg

        airflow scheduler     > "$AIRFLOW_HOME/logs/airflow-scheduler.log"     2>&1 &
        airflow dag-processor > "$AIRFLOW_HOME/logs/airflow-dag-processor.log" 2>&1 &
    else
        warn "SKIP_AIRFLOW is true => Airflow is not started"
    fi
fi
