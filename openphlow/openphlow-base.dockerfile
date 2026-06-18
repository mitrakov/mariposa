# docker build --file openphlow-base.dockerfile --tag mitrakov/openphlow-base:1.0.0 .; say hola
FROM eclipse-temurin:8
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"


# download Apache Hadoop (HADOOP_CONF_DIR is needed for Yarn)
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget --output-document=- http://mitrakoff.com/cache/hadoop-3.1.3.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hadoop-3.1.3 $HADOOP_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh


# download Apache Spark (with Scala 2.12.15)
ENV SPARK_HOME=/opt/spark
RUN wget --output-document=- http://mitrakoff.com/cache/spark-3.2.1-bin-hadoop3.2.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/spark-3.2.1-bin-hadoop3.2 $SPARK_HOME


# download Apache Zookeeper (needed for Hive and HBase)
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget --output-document=- http://mitrakoff.com/cache/apache-zookeeper-3.9.2-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-zookeeper-3.9.2-bin $ZOOKEEPER_HOME


# download Apache Hive
ENV HIVE_HOME=/opt/hive
RUN wget --output-document=- http://mitrakoff.com/cache/apache-hive-3.1.2-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-hive-3.1.2-bin $HIVE_HOME
# download a newer Postgres driver
RUN wget --directory-prefix $HIVE_HOME/lib https://jdbc.postgresql.org/download/postgresql-42.7.10.jar
# fix SLF4J multiple bindings error
RUN rm $HIVE_HOME/lib/log4j-slf4j-impl-*.jar
# fix Guava version mismatch between Hive and Hadoop
RUN rm $HIVE_HOME/lib/guava-19.0.jar && \
    cp $HADOOP_HOME/share/hadoop/common/lib/guava-27.0-jre.jar $HIVE_HOME/lib/


# download Apache HBase
ENV HBASE_HOME=/opt/hbase
RUN wget --output-document=- http://mitrakoff.com/cache/hbase-2.4.12-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/hbase-2.4.12 $HBASE_HOME
# set JAVA_HOME (must-have)
RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HBASE_HOME/conf/hbase-env.sh
# fix SLF4J multiple bindings error
# RUN rm $HBASE_HOME/lib/client-facing-thirdparty/slf4j-reload4j-*.jar


# download Apache Kafka 4.2.0 (non-Zookeeper version)
ENV KAFKA_HOME=/opt/kafka
RUN wget --output-document=- http://mitrakoff.com/cache/kafka_2.12-3.2.0.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/kafka_2.12-3.2.0 $KAFKA_HOME


# download Apache Tez 0.9.1 (for Hive)
ENV TEZ_HOME=/opt/tez
RUN wget --output-document=- http://mitrakoff.com/cache/apache-tez-0.9.1-bin.tar.gz | \
    tar --extract --gzip --directory /opt && mv /opt/apache-tez-0.9.1-bin $TEZ_HOME


# update PATH (all but tez)
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$SPARK_HOME/sbin:$HIVE_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$KAFKA_HOME/bin


# add Postgres-16 sources
RUN apt update && apt install lsb-release
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list


# sudo        start services
# openssh     quick-start services
# postgresql  Hive/HUE
# libsasl2    HUE
# mc          optional
RUN apt update && apt install --yes sudo openssh-server postgresql-16 libsasl2-modules mc && apt clean


# create user 'hadoop' and add it to sudoers
RUN useradd --create-home --shell /bin/bash hadoop
RUN echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers


# switch ownership to 'hadoop'
RUN mkdir -p $HADOOP_HOME/dfs $HADOOP_HOME/logs $ZOOKEEPER_HOME/data $KAFKA_HOME/data $HIVE_HOME/logs $AIRFLOW_HOME/dags $AIRFLOW_HOME/logs /var/log/hue /var/run/hue && \
    chown -R hadoop:hadoop $HADOOP_HOME $SPARK_HOME $ZOOKEEPER_HOME $KAFKA_HOME $HIVE_HOME $HBASE_HOME $TEZ_HOME $AIRFLOW_HOME $HUE_HOME /var/log/hue /var/run/hue


# install HashiCorp vault
ENV VAULT_HOME=/opt/vault
ENV CERTS_DIR=$VAULT_HOME/certs
RUN wget http://mitrakoff.com/cache/vault_2.0.2_linux_$(uname -m).zip && \
    unzip vault_2.0.2_linux_$(uname -m).zip -d $VAULT_HOME/ && \
    rm -f vault_2.0.2_linux_$(uname -m).zip && \
    mkdir $CERTS_DIR && \
    chown -R hadoop:hadoop $VAULT_HOME
ENV PATH=$PATH:$VAULT_HOME


# Add Kerberos
RUN apt install --yes krb5-kdc krb5-admin-server libsasl2-modules-gssapi-mit netcat-openbsd jq

# extra ENV variables and folders for Kerberos
ENV KEYTABS_DIR=/etc/security/keytabs
ENV KAFKA_OPTS="-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf"
RUN mkdir $KEYTABS_DIR && chown hadoop:hadoop $KEYTABS_DIR


# in your image, add "USER hadoop"


# TODO: move up
COPY hbase-patch-2.4.12.jar $HBASE_HOME/lib/
ENV HUE_HOME=/opt/hue
RUN mkdir $HUE_HOME && chown hadoop:hadoop $HUE_HOME
RUN rm $HBASE_HOME/lib/client-facing-thirdparty/slf4j-reload4j-*.jar

# extra shit for old Hive
RUN useradd --create-home --shell /bin/bash hive
RUN usermod -a -G hadoop hive
