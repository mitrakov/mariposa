# docker build --file flink.dockerfile --tag mitrakov/flink:1.0.0 .
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


# download Apache Flink
# original: https://downloads.apache.org/flink/flink-2.3.0/flink-2.3.0-bin-scala_2.12.tgz
ENV FLINK_HOME=/opt/flink
RUN wget --output-document=- http://mitrakoff.com/cache/flink-2.3.0-bin-scala_2.12.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/flink-2.3.0 $FLINK_HOME


# update PATH
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$FLINK_HOME/bin


RUN apt update && apt install --yes sudo openssh-server mc && apt clean


# create user 'hadoop' (if not exists!), add it to sudoers and let it SSH to other nodes
RUN useradd --create-home --shell /bin/bash hadoop || [ $? -eq 9 ]
RUN echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN su --login hadoop --command "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"


# switch ownership to 'hadoop'
RUN mkdir --parents $HADOOP_HOME/dfs $HADOOP_HOME/logs && \
    chown --recursive hadoop:hadoop $HADOOP_HOME $FLINK_HOME

# in your image, add "USER hadoop"
