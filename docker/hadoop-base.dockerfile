# docker build --file hadoop-base.dockerfile --tag mitrakov/hadoop-base:1.0.0 .
# java 17 is min for Spark 4.1.1
FROM eclipse-temurin:17
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"

# download Apache Spark 4.1.1
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- https://downloads.apache.org/spark/spark-4.1.1/spark-4.1.1-bin-hadoop3.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-4.1.1-bin-hadoop3 $SPARK_HOME

# download Apache Hadoop (Spark uses v3.4.2)
ENV HADOOP_HOME=/opt/hadoop
RUN wget --output-document=- https://downloads.apache.org/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.4.2 $HADOOP_HOME

# download Apache Hive (Spark uses v2.3.10)
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- https://archive.apache.org/dist/hive/hive-2.3.10/apache-hive-2.3.10-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-2.3.10-bin $HIVE_HOME
# download a newer Postgres driver because std Hive driver it too old and doesn't support 'scram-sha-256'
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar

# download Apache HBase 2.5.13 (do NOT use 2.6.4, it contains a bug with WAL replay)
ENV HBASE_HOME=/opt/hbase
RUN wget --output-document=- https://downloads.apache.org/hbase/2.5.13/hbase-2.5.13-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hbase-2.5.13 $HBASE_HOME

# download Apache Zookeeper 3.9.5 (Spark uses 3.9.4)
#ENV ZK_HOME=/opt/zookeeper
#RUN wget --output-document=- https://downloads.apache.org/zookeeper/zookeeper-3.9.5/apache-zookeeper-3.9.5-bin.tar.gz | \
#    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.5-bin $ZK_HOME

# Update PATH in your main Dockerfile or here
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin
