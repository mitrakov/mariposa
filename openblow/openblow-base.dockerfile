# docker build --file openblow-base.dockerfile --tag mitrakov/openblow-base:1.0.0 .
FROM eclipse-temurin:8
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"

# download Apache Spark 3.2.1 (with Scala 2.12.15)
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- https://archive.apache.org/dist/spark/spark-3.2.1/spark-3.2.1-bin-hadoop3.2.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-3.2.1-bin-hadoop3.2 $SPARK_HOME

# download Apache Hadoop (HADOOP_CONF_DIR is needed for Yarn)
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget --output-document=- https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/hadoop-3.1.3.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.1.3 $HADOOP_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh

# download Apache Hive 
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- https://archive.apache.org/dist/hive/hive-3.1.2/apache-hive-3.1.2-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-3.1.2-bin $HIVE_HOME
# download a newer Postgres driver because std Hive driver it too old and doesn't support 'scram-sha-256'
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar
# fix warning: "SLF4J: Class path contains multiple SLF4J bindings."
RUN rm $HIVE_HOME/lib/log4j-slf4j-impl-*.jar
# fix Guava version mismatch between Hive and Hadoop
RUN rm $HIVE_HOME/lib/guava-19.0.jar && \
    cp $HADOOP_HOME/share/hadoop/common/lib/guava-27.0-jre.jar $HIVE_HOME/lib/

# download Apache HBase
ENV HBASE_HOME=/opt/hbase
RUN wget --output-document=- https://archive.apache.org/dist/hbase/2.4.12/hbase-2.4.12-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hbase-2.4.12 $HBASE_HOME

# fix warning: "SLF4J: Class path contains multiple SLF4J bindings."
# RUN rm $HBASE_HOME/lib/client-facing-thirdparty/log4j-slf4j-impl-*.jar
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HBASE_HOME/conf/hbase-env.sh

# download Apache Zookeeper
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget --output-document=- https://archive.apache.org/dist/zookeeper/zookeeper-3.9.2/apache-zookeeper-3.9.2-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.2-bin $ZOOKEEPER_HOME

# download Apache Kafka
ENV KAFKA_HOME=/opt/kafka
RUN wget --output-document=- https://archive.apache.org/dist/kafka/3.2.0/kafka_2.12-3.2.0.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/kafka_2.12-3.2.0 $KAFKA_HOME

# Update PATH in your main Dockerfile or here
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin

# install sudo to start services, ssh for Hadoop, postgresql for Hive Metastore (pin version 16), iproute/mc: optional
RUN apt update && apt install -y sudo openssh-server postgresql-16 iproute2 mc && apt clean

# create user 'hadoop' and add it to sudoers (w/o password)
RUN useradd --create-home --shell /bin/bash hadoop && echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# switch ownership to 'hadoop'
RUN mkdir $HADOOP_HOME/dfs && \
    mkdir $HADOOP_HOME/logs && \
    mkdir $ZOOKEEPER_HOME/data && \
    mkdir $KAFKA_HOME/data && \
    chown -R hadoop:hadoop $SPARK_HOME && \
    chown -R hadoop:hadoop $HADOOP_HOME && \
    chown -R hadoop:hadoop $HIVE_HOME && \
    chown -R hadoop:hadoop $HBASE_HOME && \
    chown -R hadoop:hadoop $ZOOKEEPER_HOME && \
    chown -R hadoop:hadoop $KAFKA_HOME

USER hadoop

# SSH passwordless login for Hadoop
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
