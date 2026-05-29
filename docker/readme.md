# Common
```sh
kinit -kt $KEYTABS_DIR/$(hostname).keytab hadoop/$(hostname)@MARIPOSA.COM
cat /opt/hbase/logs/hbase--*.host.log
zkCli.sh -server $(hostname)
kafka-topics.sh --list --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties
kafka-console-producer.sh --bootstrap-server $(hostname):9092 --topic the-topic --command-config $KAFKA_HOME/config/sasl.properties
keytool -list -v -keystore $(hostname).keystore.jks -storepass marip0sa_jKs
keytool -list -v -keystore truststore.jks -storepass marip0sa_jKs
```

## Spark
```scala
spark.sql("CREATE TABLE hello_world (id INT, data STRING) USING hive")
spark.sql("INSERT INTO hello_world VALUES (1, 'It is working')")
spark.sql("SELECT * FROM hello_world").show()
```

# Tommy
```sh
kinit -kt $KEYTABS_DIR/tommy.keytab $(whoami)@MARIPOSA.COM
hdfs dfs -ls /
```
/home/tommy/kafka_jaas.conf:
```sh
KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useTicketCache=true
    serviceName=kafka;
};
```
/home/tommy/kafka.properties:
```
security.protocol=SASL_SSL
ssl.truststore.location=/opt/hadoop/etc/hadoop/certs/truststore.jks
ssl.truststore.password=marip0sa_jKs
```

```sh
export KAFKA_OPTS="-Djava.security.auth.login.config=/home/tommy/kafka_jaas.conf"
kinit -kt $KEYTABS_DIR/tommy.keytab $(whoami)@MARIPOSA.COM
kafka-topics.sh --list --bootstrap-server $(hostname):9092 --command-config ~/kafka.properties
kafka-console-producer.sh --bootstrap-server $(hostname):9092 --topic the-topic --command-config ~/kafka.properties
```

# Building HBase patch
- download sources for exact HBase version (e.g. 2.5.13)
- find shitty method, e.g. `"FSDataInputStreamWrapper::updateInputStreamStatistics()"` and skip it (e.g. `if (true) return;`)
- copy-paste this file into your docker container, following the full java path (e.g. `org/apache/hadoop/hbase/io/FSDataInputStreamWrapper.java`)
- run:

```sh
javac -cp "$(hbase classpath)" $PATCH_DIR/org/apache/hadoop/hbase/io/FSDataInputStreamWrapper.java
jar cvf mariposa-hbase-patch-2.5.13.jar -C $PATCH_DIR .
```


## Tez
```sh
echo "aaa bbb ccc aaa bbb aaa" > f.txt
hdfs dfs -put f.txt /apps/tez/f.txt
hadoop jar $TEZ_HOME/tez-examples-0.10.5.jar orderedwordcount /apps/tez/f.txt /apps/tez/out
```


## Beeline
```sh
beeline -u jdbc:hive2://localhost:10000 -n hadoop
```
```sql
set hive.execution.engine;
create table your_table(id string);
INSERT INTO your_table VALUES ('444');
SELECT * FROM your_table;
```
