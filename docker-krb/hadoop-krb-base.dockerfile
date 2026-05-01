# docker build --file hadoop-krb-base.dockerfile --tag mitrakov/hadoop-krb-base:1.0.0 . && say hola
# java 17 is min for Spark 4.1.1
FROM eclipse-temurin:17
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"

# download Apache Hadoop (HADOOP_CONF_DIR is needed for Yarn)
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget --output-document=- https://downloads.apache.org/hadoop/common/hadoop-3.5.0/hadoop-3.5.0.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.5.0 $HADOOP_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh

# download Apache Spark 4.1.1 (with Scala 2.13.17)
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- https://downloads.apache.org/spark/spark-4.1.1/spark-4.1.1-bin-hadoop3.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-4.1.1-bin-hadoop3 $SPARK_HOME

# download Apache Zookeeper 3.9.5 (needed for Hive and HBase)
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget --output-document=- https://downloads.apache.org/zookeeper/zookeeper-3.9.5/apache-zookeeper-3.9.5-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.5-bin $ZOOKEEPER_HOME

# download Apache Hive (4.1.0 because 4.2.0 requires jdk-21)
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- https://archive.apache.org/dist/hive/hive-4.1.0/apache-hive-4.1.0-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-4.1.0-bin $HIVE_HOME
# download a newer Postgres driver because std Hive driver it too old and doesn't support 'scram-sha-256'
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar

# update PATH
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin

# install packages (netcat for nc)
RUN apt update && apt install --yes sudo openssh-server krb5-kdc krb5-admin-server postgresql-16 netcat-openbsd iproute2 mc && apt clean

# fix warning: "SLF4J: Class path contains multiple SLF4J bindings."
RUN rm $HIVE_HOME/lib/log4j-slf4j-impl-*.jar

# create user 'hadoop' and add it to sudoers (w/o password)
RUN useradd --create-home --shell /bin/bash hadoop && echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# switch ownership to 'hadoop'
RUN mkdir $HADOOP_HOME/dfs $HADOOP_HOME/logs && \
    mkdir $ZOOKEEPER_HOME/data && \
    chown -R hadoop:hadoop $HADOOP_HOME && \
    chown -R hadoop:hadoop $ZOOKEEPER_HOME && \
    chown -R hadoop:hadoop $HIVE_HOME

ENV KEYTABS_DIR=/etc/security/keytabs

USER hadoop
