#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --deploy-mode cluster \
  --driver-memory 600m \
  --executor-memory 1g \
  --executor-cores 1 \
  --num-executors 2 \
  --driver-java-options=" \
   -Dapp.hive.table=zakupki.fz223_import \
   -Dapp.kafka.topic=zakupki-fz223-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  mariposa-assembly-1.0.0.jar &
