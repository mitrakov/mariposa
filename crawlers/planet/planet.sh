#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --name "Kafka2Hive-planet-import" \
  --deploy-mode cluster \
  --queue mariposa \
  --driver-java-options=" \
   -Dapp.hive.table=planet.t_import \
   -Dapp.kafka.topic=planet-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-*.jar


spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar PlanetRefineJob.scala


java -jar /home/hadoop/mariposa-scraper-assembly-*.jar /home/hadoop/apps/PlanetScraper.scala


spark-submit \
  --name "Kafka2Hive-planet-import" \
  --driver-java-options=" \
   -Dapp.hbase.table=planet:cards \
   -Dapp.hive.sql.text='SELECT * FROM planet.refine WHERE city = \"Санкт-Петербург\";' \
   -Dapp.kafka.run.infinitely=true" \
  --class com.mitrakoff.mariposa.Hive2HBase \
  /home/hadoop/mariposa-assembly-*.jar
