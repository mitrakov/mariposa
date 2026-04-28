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
RUN echo "export JSVC_HOME=/usr/bin"   >> $HADOOP_CONF_DIR/hadoop-env.sh

# update PATH
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

# install sudo to start services, ssh for Hadoop, postgresql for Hive Metastore and Airflow (pin version 16), iproute/mc: optional
RUN apt update && apt install -y sudo openssh-server postgresql-16 krb5-kdc krb5-admin-server krb5-user jsvc iproute2 mc && apt clean

# create user 'hadoop' and add it to sudoers (w/o password)
RUN useradd --create-home --shell /bin/bash hadoop && echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# switch ownership to 'hadoop'
RUN mkdir $HADOOP_HOME/dfs $HADOOP_HOME/logs && \
    chown -R hadoop:hadoop $HADOOP_HOME

RUN echo "export HDFS_DATANODE_SECURE_USER=hadoop" >> $HADOOP_CONF_DIR/hadoop-env.sh
USER hadoop
