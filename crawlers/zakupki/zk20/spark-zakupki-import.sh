#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --deploy-mode cluster \
  --driver-java-options=" \
   -Dapp.hive.table=zakupki.zk20_import \
   -Dapp.kafka.topic=zakupki-zk20-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  mariposa-assembly-1.0.0.jar &
