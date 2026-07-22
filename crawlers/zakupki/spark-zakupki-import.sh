#!/usr/bin/env bash
set -euo pipefail

JKS_PASSWORD=...
source /etc/profile.d/mariposa.sh
spark-submit \
  --name "Kafka2Hive-fz223-import" \
  --deploy-mode cluster \
  --queue queue2 \
  --driver-memory 2g \
  --executor-memory 1600m \
  --driver-java-options=" \
   -Dapp.hive.table=zakupki.fz223_import \
   -Dapp.kafka.topic=zakupki-fz223-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  mariposa-assembly-1.0.1.jar &
