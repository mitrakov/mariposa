# docker build --file hadoop-base.dockerfile --tag mitrakov/hadoop-base:1.0.0 . && say hola
# java 17 is min for Spark 4.1.1
FROM eclipse-temurin:17
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"

# download Apache Spark 4.1.1 (with Scala 2.13.17)
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- https://downloads.apache.org/spark/spark-4.1.1/spark-4.1.1-bin-hadoop3.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-4.1.1-bin-hadoop3 $SPARK_HOME

# download Apache Hadoop (HADOOP_CONF_DIR is needed for Yarn)
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget --output-document=- https://downloads.apache.org/hadoop/common/hadoop-3.5.0/hadoop-3.5.0.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.5.0 $HADOOP_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh

# download Apache Hive (4.1.0 because 4.2.0 requires jdk-21)
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- https://archive.apache.org/dist/hive/hive-4.1.0/apache-hive-4.1.0-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-4.1.0-bin $HIVE_HOME
# download a newer Postgres driver because std Hive driver it too old and doesn't support 'scram-sha-256'
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar

# download Apache HBase 2.5.13 (2.5.13 is a latest stable release, do NOT use 2.6.4, it contains a bug with WAL replay)
ENV HBASE_HOME=/opt/hbase
RUN wget --output-document=- https://downloads.apache.org/hbase/2.5.13/hbase-2.5.13-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hbase-2.5.13 $HBASE_HOME
# add HBase-Spark connector
RUN wget --directory-prefix $SPARK_HOME/jars/ http://mitrakoff.com/jars/hbase-spark-1.1.0.jar
RUN wget --directory-prefix $SPARK_HOME/jars/ http://mitrakoff.com/jars/hbase-spark-protocol-shaded-1.1.0.jar
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HBASE_HOME/conf/hbase-env.sh

# download Apache Zookeeper 3.9.5 (needed for Hive, HBase and old-school Kafka)
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget --output-document=- https://downloads.apache.org/zookeeper/zookeeper-3.9.5/apache-zookeeper-3.9.5-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.5-bin $ZOOKEEPER_HOME

# download Apache Kafka 4.2.0 (non-Zookeeper version)
ENV KAFKA_HOME=/opt/kafka
RUN wget --output-document=- https://downloads.apache.org/kafka/4.2.0/kafka_2.13-4.2.0.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/kafka_2.13-4.2.0 $KAFKA_HOME

# update PATH
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin

# install sudo to start services, ssh for Hadoop, postgresql for Hive Metastore and Airflow (pin version 16), iproute/mc: optional
RUN apt update && apt install -y sudo openssh-server postgresql-16 iproute2 mc && apt clean

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

# copy-paste HUE and fix "encodebytes" function
ENV HUE_HOME=/opt/hue
COPY --from=mitrakov/hadoop-hue:1.0.0 $HUE_HOME $HUE_HOME
COPY --from=mitrakov/hadoop-hue:1.0.0 /usr/local/bin/python3.11 /usr/local/bin/python3.11
COPY --from=mitrakov/hadoop-hue:1.0.0 /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=mitrakov/hadoop-hue:1.0.0 /usr/local/lib/libpython3.11* /usr/local/lib/
RUN sed -i "s/_b64_decode_fn = getattr(base64, 'decodebytes', base64.decodestring)/_b64_decode_fn = base64.decodebytes/g" $HUE_HOME/desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
RUN sed -i "s/_b64_encode_fn = getattr(base64, 'encodebytes', base64.encodestring)/_b64_encode_fn = base64.encodebytes/g" $HUE_HOME/desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py

# fix warning: "SLF4J: Class path contains multiple SLF4J bindings."
RUN rm $HIVE_HOME/lib/log4j-slf4j-impl-*.jar
RUN rm $HBASE_HOME/lib/client-facing-thirdparty/log4j-slf4j-impl-*.jar

# create user 'hadoop' and add it to sudoers (w/o password)
RUN useradd --create-home --shell /bin/bash hadoop && echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# switch ownership to 'hadoop'
RUN mkdir $HADOOP_HOME/dfs && \
    mkdir $HADOOP_HOME/logs && \
    mkdir $ZOOKEEPER_HOME/data && \
    mkdir $KAFKA_HOME/data && \
    mkdir -p $AIRFLOW_HOME/dags && \
    chown -R hadoop:hadoop $HADOOP_HOME && \
    chown -R hadoop:hadoop $HIVE_HOME && \
    chown -R hadoop:hadoop $HBASE_HOME && \
    chown -R hadoop:hadoop $ZOOKEEPER_HOME && \
    chown -R hadoop:hadoop $KAFKA_HOME && \
    chown -R hadoop:hadoop $AIRFLOW_HOME && \
    chown -R hadoop:hadoop $HUE_HOME

USER hadoop

# SSH passwordless login for Hadoop
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
