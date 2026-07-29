#!/usr/bin/env bash
# Apache Zookeeper
set -euo pipefail
. utils.sh
. .env

check_env "KEYTABS_DIR"
check_env "MY_HOSTNAME"
check_env "ZK_ID"
check_env "ZOOKEEPER_HOME"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_file "$KEYTABS_DIR/$MY_HOSTNAME.keytab"


# ZK_ID must be a unique number for every node, e.g. 1,2,3
echo "$ZK_ID" > $ZOOKEEPER_HOME/data/myid
{
  echo 'export SERVER_JVMFLAGS="$SERVER_JVMFLAGS -Djava.security.auth.login.config=$ZOOKEEPER_HOME/conf/jaas.conf"'
  echo 'export CLIENT_JVMFLAGS="$CLIENT_JVMFLAGS -Djava.security.auth.login.config=$ZOOKEEPER_HOME/conf/jaas.conf"'
} >> $ZOOKEEPER_HOME/bin/zkEnv.sh

cat <<EOF > $ZOOKEEPER_HOME/conf/zoo.cfg
tickTime=1000
initLimit=10
syncLimit=5
dataDir=$ZOOKEEPER_HOME/data
clientPort=2181

authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
requireClientAuthScheme=sasl

server.1=$MASTER_HOST:2888:3888
EOF

count=2     # "1" is already set for $MASTER_HOST
IFS=','
for worker in $WORKER_HOSTS; do
    echo "server.$count=$worker:2888:3888" >> $ZOOKEEPER_HOME/conf/zoo.cfg
    count=$((count + 1))
done
unset IFS

cat <<EOF > $ZOOKEEPER_HOME/conf/jaas.conf
Server {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    useTicketCache=false
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="zookeeper/$MY_HOSTNAME@MARIPOSA.COM"
    storeKey=true;
};

Client {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    useTicketCache=false
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="zookeeper/$MY_HOSTNAME@MARIPOSA.COM"
    storeKey=true;
};
EOF


log "Starting Zookeeper..."
rm --verbose --force $ZOOKEEPER_HOME/data/zookeeper_server.pid       # in case of hard shutdown
zkServer.sh start
