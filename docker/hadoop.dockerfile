# docker build --file hadoop.dockerfile --tag mitrakov/hadoop:1.0.0 .; say hola
# java 17 is min for Spark 4.1.1
FROM eclipse-temurin:17
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"


# download Apache Hadoop (HADOOP_CONF_DIR is needed for Yarn)
# original: https://downloads.apache.org/hadoop/common/hadoop-3.5.0/hadoop-3.5.0.tar.gz
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget --output-document=- http://mitrakoff.com/cache/hadoop-3.5.0.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.5.0 $HADOOP_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh


# download Apache Spark 4.1.1 (with Scala 2.13.17)
# original: https://archive.apache.org/dist/spark/spark-4.1.1/spark-4.1.1-bin-hadoop3.tgz
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- http://mitrakoff.com/cache/spark-4.1.1-bin-hadoop3.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-4.1.1-bin-hadoop3 $SPARK_HOME


# download Apache Zookeeper 3.9.5 (needed for Hive and HBase)
# original: https://downloads.apache.org/zookeeper/zookeeper-3.9.5/apache-zookeeper-3.9.5-bin.tar.gz
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget --output-document=- http://mitrakoff.com/cache/apache-zookeeper-3.9.5-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.5-bin $ZOOKEEPER_HOME


# download Apache Hive (4.1.0 because 4.2.0 requires jdk-21)
# original: https://archive.apache.org/dist/hive/hive-4.1.0/apache-hive-4.1.0-bin.tar.gz
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- http://mitrakoff.com/cache/apache-hive-4.1.0-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-4.1.0-bin $HIVE_HOME
# download a newer Postgres driver because std Hive driver it too old and doesn't support 'scram-sha-256'
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar
# fix SLF4J multiple bindings error
RUN rm $HIVE_HOME/lib/log4j-slf4j-impl-*.jar


# download Apache HBase 2.5.14 (2.5.14 is a latest stable release, do NOT use 2.6.4, it contains a bug with WAL replay)
# original: https://downloads.apache.org/hbase/2.5.14/hbase-2.5.14-bin.tar.gz
ENV HBASE_HOME=/opt/hbase
RUN wget --output-document=- http://mitrakoff.com/cache/hbase-2.5.14-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hbase-2.5.14 $HBASE_HOME
# add HBase-Spark connector
RUN wget --directory-prefix $SPARK_HOME/jars/ http://mitrakoff.com/cache/hbase-spark-1.1.0.jar
RUN wget --directory-prefix $SPARK_HOME/jars/ http://mitrakoff.com/cache/hbase-spark-protocol-shaded-1.1.0.jar
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HBASE_HOME/conf/hbase-env.sh
# fix SLF4J multiple bindings error
RUN rm $HBASE_HOME/lib/client-facing-thirdparty/log4j-slf4j-impl-*.jar
# patch HBase
COPY mariposa-hbase-patch-2.5.13.jar $HBASE_HOME/lib/


# download Apache Kafka 4.2.0 (non-Zookeeper version)
# original: https://downloads.apache.org/kafka/4.2.0/kafka_2.13-4.2.0.tgz
ENV KAFKA_HOME=/opt/kafka
RUN wget --output-document=- http://mitrakoff.com/cache/kafka_2.13-4.2.0.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/kafka_2.13-4.2.0 $KAFKA_HOME


# download Apache Tez 0.10.5 (for Hive)
# original: https://downloads.apache.org/tez/0.10.5/apache-tez-0.10.5-bin.tar.gz
ENV TEZ_HOME=/opt/tez
RUN wget --output-document=- http://mitrakoff.com/cache/apache-tez-0.10.5-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-tez-0.10.5-bin $TEZ_HOME


# update PATH (all but tez)
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin


# add Postgres-16 sources
RUN apt update && apt install lsb-release
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list


# sudo        start services
# openssh     quick-start services (DEV only)
# postgresql  Hive/Airflow/HUE
# libsasl2    HUE (even for DEV!)
# mc          optional
RUN apt update && apt install --yes sudo openssh-server postgresql-16 libsasl2-modules mc && apt clean


# copy-paste Apache Airflow
ENV AIRFLOW_HOME=/opt/airflow
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/python3.12 /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/python3 /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/pip3* /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/airflow /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/celery /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/uvicorn /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/fastapi /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/bin/alembic /usr/local/bin/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/lib/python3.12/ /usr/local/lib/python3.12/
COPY --from=mitrakov/hadoop-airflow:1.0.0 /usr/local/lib/libpython3.12* /usr/local/lib/


# copy-paste HUE
ENV HUE_HOME=/opt/hue
COPY --from=mitrakov/hadoop-hue:1.0.0 /usr/bin/python3.9 /usr/bin/python3.9
COPY --from=mitrakov/hadoop-hue:1.0.0 /usr/lib/python3.9 /usr/lib/python3.9
COPY --from=mitrakov/hadoop-hue:1.0.0 $HUE_HOME $HUE_HOME


# create user 'hadoop' and add it to sudoers (keep 2 sep. commands to avoid errors "useradd: user 'hadoop' already exists")
RUN useradd --create-home --shell /bin/bash hadoop
RUN echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers


# switch ownership to 'hadoop'
RUN mkdir -p $HADOOP_HOME/dfs $HADOOP_HOME/logs $ZOOKEEPER_HOME/data $KAFKA_HOME/data $HIVE_HOME/logs $AIRFLOW_HOME/dags $AIRFLOW_HOME/logs /var/log/hue /var/run/hue && \
    chown -R hadoop:hadoop $HADOOP_HOME $ZOOKEEPER_HOME $KAFKA_HOME $HIVE_HOME $HBASE_HOME $TEZ_HOME $AIRFLOW_HOME $HUE_HOME /var/log/hue /var/run/hue


# in your image, add "USER hadoop"
