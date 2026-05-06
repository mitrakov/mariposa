# Common
```sh
cat /opt/hbase/logs/hbase--*.host.log
zkCli.sh -server $(hostname)
kafka-topics.sh --list --bootstrap-server $(hostname):9092 --command-config $KAFKA_HOME/config/sasl.properties
```

# Tommy
```sh
kinit -kt $KEYTABS_DIR/tommy.keytab $(whoami)@MARIPOSA.COM
hdfs dfs -ls /
```

## Spark
```scala
spark.sql("CREATE TABLE hello_world (id INT, data STRING) USING hive")
spark.sql("INSERT INTO hello_world VALUES (1, 'It is working')")
spark.sql("SELECT * FROM hello_world").show()
```

## Kafka
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

```
export KAFKA_OPTS="-Djava.security.auth.login.config=/home/tommy/kafka_jaas.conf"
kinit -kt $KEYTABS_DIR/tommy.keytab $(whoami)@MARIPOSA.COM
kafka-topics.sh --list --bootstrap-server $(hostname):9092 --command-config ~/kafka.properties
kafka-console-producer.sh --bootstrap-server $(hostname):9092 --topic the-topic --command-config ~/kafka.properties
```
