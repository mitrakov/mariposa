#!/usr/bin/env bash
# Apache Kafka
set -euo pipefail
. utils.sh
. .env

check_env "MY_KEYSTORE"
check_env "TRUSTSTORE"
check_env "KEYTABS_DIR"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "KAFKA_HOME"
check_env "ZK_ID"
check_env "JKS_PASSWORD"
check_file "$MY_KEYSTORE"
check_file "$TRUSTSTORE"
check_file "$KEYTABS_DIR/$(hostname).keytab"


# format: id1@host1:9093,id2@host2:9093,id3@host3:9093 (hardcoding the master as ID 1 and workers starting from 2)
VOTERS="1@$MASTER_HOST:9093"
count=2
IFS=','
for worker in $WORKER_HOSTS; do
    VOTERS="$VOTERS,$count@$worker:9093"
    count=$((count + 1))
done
unset IFS

cat <<EOF > $KAFKA_HOME/config/server.properties
# Role: every node acts as both a Broker and a Controller
process.roles=broker,controller
node.id=$ZK_ID
controller.quorum.voters=$VOTERS

# Network settings
listeners=SASL_SSL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
inter.broker.listener.name=SASL_SSL
advertised.listeners=SASL_SSL://$(hostname):9092
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:SASL_SSL,SASL_SSL:SASL_SSL

# Kerberos settings
sasl.enabled.mechanisms=GSSAPI
sasl.mechanism.inter.broker.protocol=GSSAPI
sasl.mechanism.controller.protocol=GSSAPI
sasl.kerberos.service.name=kafka

# SSL Settings
ssl.keystore.location=$MY_KEYSTORE
ssl.keystore.password=$JKS_PASSWORD
ssl.key.password=$JKS_PASSWORD
ssl.truststore.location=$TRUSTSTORE
ssl.truststore.password=$JKS_PASSWORD
ssl.endpoint.identification.algorithm=HTTPS

# Log & Data
log.dirs=$KAFKA_HOME/data
num.partitions=3
offsets.topic.replication.factor=3
EOF

cat <<EOF > $KAFKA_HOME/config/kafka_jaas.conf
KafkaServer {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="$KEYTABS_DIR/$(hostname).keytab"
    principal="kafka/$(hostname)@MARIPOSA.COM";
};

KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="$KEYTABS_DIR/$(hostname).keytab"
    principal="kafka/$(hostname)@MARIPOSA.COM";
};
EOF

cat <<EOF > $KAFKA_HOME/config/sasl.properties
security.protocol=SASL_SSL
sasl.kerberos.service.name=kafka
ssl.truststore.location=$TRUSTSTORE
ssl.truststore.password=$JKS_PASSWORD
EOF


log "Starting Kafka Server..."
if [ ! -f "$KAFKA_HOME/data/meta.properties" ]; then
    log "First time run. Formatting Kafka storage"
    KAFKA_CLUSTER_ID=$(vault kv get -field=cluster_id secret/hadoop/kafka)
    check_env "KAFKA_CLUSTER_ID"
    $KAFKA_HOME/bin/kafka-storage.sh format --cluster-id $KAFKA_CLUSTER_ID --config $KAFKA_HOME/config/server.properties
else
    info "OK: Kafka storage already formatted"
fi
kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties
