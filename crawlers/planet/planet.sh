#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --name "Kafka2Hive-planet-import" \
  --deploy-mode cluster \
  --queue mariposa \
  --principal $(whoami)/$MASTER_HOST@MARIPOSA.COM \
  --keytab $KEYTABS_DIR/$MASTER_HOST.keytab \
  --driver-java-options=" \
   -Dapp.hive.table=planet.t_import \
   -Dapp.kafka.topic=planet-import \
   -Dapp.kafka.run.infinitely=true \
   -Dapp.security.truststore.password=$JKS_PASSWORD \
   -Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --conf "spark.executor.extraJavaOptions=-Djava.security.auth.login.config=$KAFKA_HOME/config/kafka_jaas.conf" \
  --class com.mitrakoff.mariposa.Kafka2Hive \
  /home/hadoop/mariposa-assembly-*.jar &


JKS_PASSWORD=... java -jar /home/hadoop/mariposa-scraper-assembly-*.jar PlanetScraper.scala > /home/hadoop/logs/$0.log 2>&1 &


spark-submit --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar PlanetRefineJob.scala


spark-submit \
  --name "Hive2HBase-planet" \
  --driver-java-options=" \
   -Dapp.hbase.table=planet:cards \
   -Dapp.hive.sql.text='SELECT * FROM planet.refine WHERE city = \"Санкт-Петербург\";'" \
  --class com.mitrakoff.mariposa.Hive2HBase \
  /home/hadoop/mariposa-assembly-*.jar
