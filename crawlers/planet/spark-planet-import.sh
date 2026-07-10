#!/usr/bin/env bash

JKS_PASSWORD=...
/opt/spark/bin/spark-submit \
  --name "Mariposa-Kafka2Hive-planet-import" \
  --deploy-mode cluster \
  --driver-memory 530m \
  --executor-memory 820m \
  --executor-cores 1 \
  --num-executors 2 \
  --driver-java-options=" \
   -Dapp.hive.table=planet.t_import \
   -Dapp.kafka.topic=planet-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=/opt/kafka/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=/opt/kafka/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-1.0.0.jar &
