#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --name "Kafka2Hive-hh-import" \
  --deploy-mode cluster \
  --queue mariposa \
  --driver-java-options=" \
   -Dapp.hive.table=hh.t_import \
   -Dapp.kafka.topic=hh-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-*.jar &


JKS_PASSWORD=... java -jar /home/hadoop/mariposa-scraper-assembly-*.jar HhScraper.scala > /home/hadoop/logs/$0 2>&1 &


spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar HhRefineJob.scala
