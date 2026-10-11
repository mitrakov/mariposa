#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --name "Kafka2Hive-fz223-import" \
  --deploy-mode cluster \
  --queue mariposa \
  --driver-java-options=" \
   -Dapp.hive.table=zakupki.fz223_import \
   -Dapp.kafka.topic=zakupki-fz223-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-*.jar &


JKS_PASSWORD=... java -jar /home/hadoop/mariposa-scraper-assembly-*.jar Fz223Scraper.scala > /home/hadoop/logs/$0.log 2>&1 &
