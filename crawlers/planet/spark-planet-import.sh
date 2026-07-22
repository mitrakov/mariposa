#!/usr/bin/env bash
set -euo pipefail

JKS_PASSWORD=...
source /etc/profile.d/mariposa.sh
spark-submit \
  --name "Kafka2Hive-planet-import" \
  --deploy-mode cluster \
  --queue default \
  --driver-memory 3g \
  --executor-memory 3g \
  --driver-java-options=" \
   -Dapp.hive.table=planet.t_import \
   -Dapp.kafka.topic=planet-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-1.0.1.jar &
