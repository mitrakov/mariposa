# docker build --file airflow.dockerfile --tag mitrakov/hadoop-airflow:1.0.0 .
FROM python:3.12-slim-bookworm AS builder
ENV AIRFLOW_HOME=/opt/airflow
RUN pip install --no-cache-dir "apache-airflow[celery]==3.0.6" "psycopg2-binary" "asyncpg" \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.0.6/constraints-3.12.txt"
RUN pip install --no-cache-dir "apache-airflow-providers-apache-spark"
