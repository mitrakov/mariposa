#!/usr/bin/env bash

JKS_PASSWORD=...
spark-submit \
  --name "Kafka2Hive-planet-import" \
  --deploy-mode cluster \
  --queue mariposa \
  --principal $(whoami)/$MASTER_HOST@MARIPOSA.COM \
  --keytab $KEYTABS_DIR/$MASTER_HOST.keytab \
  --driver-memory 1g \
  --executor-memory 1g \
  --num-executors 4 \
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
kill `ps x | grep PlanetScraper.scala | head -1 | awk '{print $1}'`


spark-submit --num-executors 5 --class com.mitrakoff.mariposa.fly.MariposaFly /home/hadoop/mariposa-fly-*.jar PlanetRefineJob.scala
spark-submit --driver-java-options="-Dapp.hbase.table=planet:${0:2:-3} -Dapp.hive.sql.file=${0:2:-3}.sql" --class com.mitrakoff.mariposa.Hive2HBase /home/hadoop/mariposa-assembly-*.jar


# gender by city
SELECT city, COUNT(*) as total,
    ROUND((COUNT(CASE WHEN gender = 'man'   THEN 1 END) * 100.0) / COUNT(*), 2) as men,
    ROUND((COUNT(CASE WHEN gender = 'woman' THEN 1 END) * 100.0) / COUNT(*), 2) as women
FROM planet.refine
WHERE gender != 'unknown'
GROUP BY city
HAVING total > 250;

# kids by woman
SELECT personal_children AS children,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percent
FROM planet.refine
WHERE gender = 'woman'
--  AND personal_children IS NOT NULL
GROUP BY personal_children;
