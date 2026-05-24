#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-krb:1.0.0
set -euo pipefail

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
function debug() { echo -e "${PURPLE}$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] $1${NC}"; }
function log()   { echo -e "${GREEN}$(date +'%Y-%m-%d %H:%M:%S') [LOG]   $1${NC}"; }
function info()  { echo -e "${BLUE}$(date +'%Y-%m-%d %H:%M:%S') [INFO]  $1${NC}"; }
function warn()  { echo -e "${YELLOW}$(date +'%Y-%m-%d %H:%M:%S') [WARN]  $1${NC}"; }
function error() { echo -e "${RED}$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1${NC}"; }
function check_env() {
    if [[ -z "${!1:-}" ]]; then
        error "Error: environment variable '$1' is not set or empty"
        exit 1
    else
        local lower_name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_name" == *"password"* ]]; then
            info "$1: **********"
        else
            info "$1: ${!1}"
        fi
    fi
}



# checks
check_env "JAVA_HOME"
check_env "SPARK_HOME"
check_env "HADOOP_HOME"
check_env "HIVE_HOME"
check_env "ZOOKEEPER_HOME"
check_env "HBASE_HOME"
check_env "KAFKA_HOME"
check_env "AIRFLOW_HOME"
check_env "HUE_HOME"
check_env "HADOOP_CONF_DIR"
check_env "KEYTABS_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "JKS_PASSWORD"
check_env "KAFKA_CLUSTER_ID"
check_env "ZK_ID"


# DO NOT use _HOST in XML Configs! Use $MY_HOSTNAME (or $MASTER_HOST) instead!
MY_HOSTNAME=$(hostname)

# generate temp self-signed SSL certificate to enable SASL to auth data transfer protocol
# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
MY_KEYSTORE="$HADOOP_CONF_DIR/certs/$MY_HOSTNAME.keystore.jks"
TRUSTSTORE="$HADOOP_CONF_DIR/certs/truststore.jks"

if [ ! -f "$MY_KEYSTORE" ]; then
    log "Generating SSL for $MY_HOSTNAME..."

    # 1. Create node-specific keystore
    keytool -genkeypair -alias "$MY_HOSTNAME" -keyalg RSA -validity 9999 \
      -keystore "$MY_KEYSTORE" \
      -storepass "$JKS_PASSWORD" -keypass "$JKS_PASSWORD" \
      -dname "CN=$MY_HOSTNAME" -ext "SAN=dns:$MY_HOSTNAME" \
      -storetype PKCS12 -noprompt

    # 2. Export this node's certificate
    keytool -export -alias "$MY_HOSTNAME" \
      -file $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer \
      -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD"

    # 3. Import into the SHARED truststore
    sleep $ZK_ID    # must-have to avoid race-conditions!
    keytool -import -alias "$MY_HOSTNAME" \
      -file $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer \
      -keystore "$TRUSTSTORE" \
      -storepass "$JKS_PASSWORD" -noprompt

    rm -vf $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer
    info "SSL certificates stored in $MY_KEYSTORE"
else
    info "OK: Keystore already exists: $MY_KEYSTORE"
fi


# start Postgres
if [[ "$IS_MASTER" == "true" ]]; then
    log "Starting PostgreSQL..."
    PG_DATA_DIR="/var/lib/postgresql/16/main"

    sudo chown -R postgres:postgres /var/lib/postgresql/16
    if [ ! -s "$PG_DATA_DIR/PG_VERSION" ]; then
        log "First time run. Initializing PostgreSQL database..."
        sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D "$PG_DATA_DIR"        # initdb must be run as the postgres user
    else
        info "OK: Database exists in $PG_DATA_DIR"
    fi
    sudo service postgresql start

    check_env "HIVE_DB_PASSWORD"
    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hive';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hive' user and 'metastore_db'..."
        sudo -u postgres psql --command "CREATE USER hive WITH PASSWORD '$HIVE_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE metastore_db OWNER hive;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE metastore_db TO hive;"
        info "PostgreSQL user 'hive' and database 'metastore_db' created"
    else
        info "OK: user 'hive' exists"
    fi

    check_env "AIRFLOW_DB_PASSWORD"
    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='airflow';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'airflow' user and 'airflow_db'..."
        sudo -u postgres psql --command "CREATE USER airflow WITH PASSWORD '$AIRFLOW_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE airflow_db OWNER airflow;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow;"
        info "PostgreSQL user 'airflow' and database 'airflow_db' created"
    else
        info "OK: user 'airflow' exists"
    fi

    check_env "HUE_DB_PASSWORD"
    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hue';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hue' user and 'hue_db'..."
        sudo -u postgres psql --command "CREATE USER hue WITH PASSWORD '$HUE_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE hue_db OWNER hue;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE hue_db TO hue;"
        log "PostgreSQL user 'hue' and database 'hue_db' created."
    else
        info "OK: user 'hue' exists"
    fi
fi

log "Creating configs..."

# setup Kerberos
cat << EOF | sudo tee /etc/krb5.conf
[libdefaults]
    default_realm = MARIPOSA.COM
    ticket_lifetime = 24h
    renew_lifetime = 7d

[realms]
    MARIPOSA.COM = {
        kdc = $MASTER_HOST
    }
EOF

# for HUE to renew TGT
cat << EOF | sudo tee /etc/krb5kdc/kdc.conf
[realms]
    MARIPOSA.COM = {
        max_life = 24h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF

# create simple kadm5.acl to avoid startup errors
echo "*/admin@MARIPOSA.COM *" | sudo tee /etc/krb5kdc/kadm5.acl

# minimal setup for HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
    <property>
        <name>hadoop.security.authentication</name>
        <value>kerberos</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.groups</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.hosts</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.groups</name>
        <value>*</value>
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.hosts</name>
        <value>*</value>
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
    </property>
</configuration>
EOF



# minimal HDFS setup
cat <<EOF > $HADOOP_CONF_DIR/hdfs-site.xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>2</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>$HADOOP_HOME/dfs/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>$HADOOP_HOME/dfs/data</value>
    </property>
    <property>
        <name>dfs.namenode.kerberos.principal</name>
        <value>hadoop/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>hadoop/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.datanode.keytab.file</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
    <property>
        <name>dfs.data.transfer.protection</name>
        <value>authentication</value>
    </property>
    <property>
        <name>dfs.datanode.address</name>
        <value>0.0.0.0:10019</value>
        <description>https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode</description>
    </property>
    <property>
        <name>dfs.http.policy</name>
        <value>HTTPS_ONLY</value>
        <description>https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode</description>
    </property>
    <property>
        <name>dfs.block.access.token.enable</name>
        <value>true</value>
        <description>FIX: Security is enabled but block access tokens aren't enabled</description>
    </property>
</configuration>
EOF

# Kerberos setup for Yarn
cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
    </property>
    <property>
        <name>yarn.resourcemanager.principal</name>
        <value>hadoop/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>yarn.nodemanager.principal</name>
        <value>hadoop/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.nodemanager.keytab</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
</configuration>
EOF

# this is necessary for SASL data-transfer protocol to enable https
cat <<EOF > $HADOOP_CONF_DIR/ssl-server.xml
<configuration>
  <property>
    <name>ssl.server.keystore.location</name>
    <value>$MY_KEYSTORE</value>
  </property>
  <property>
    <name>ssl.server.keystore.password</name>
    <value>$JKS_PASSWORD</value>
  </property>
  <property>
    <name>ssl.server.keystore.keypassword</name>
    <value>$JKS_PASSWORD</value>
  </property>
</configuration>
EOF


# setup Apache Spark
export HBASE_LIBS="$HBASE_HOME/lib/hbase-client-2.5.13.jar:\
$HBASE_HOME/lib/hbase-common-2.5.13.jar:\
$HBASE_HOME/lib/hbase-protocol-2.5.13.jar:\
$HBASE_HOME/lib/hbase-protocol-shaded-2.5.13.jar:\
$HBASE_HOME/lib/hbase-server-2.5.13.jar:\
$HBASE_HOME/lib/hbase-mapreduce-2.5.13.jar:\
$HBASE_HOME/lib/hbase-shaded-miscellaneous-4.1.12.jar:\
$HBASE_HOME/lib/hbase-shaded-protobuf-4.1.12.jar:\
$HBASE_HOME/lib/hbase-shaded-netty-4.1.12.jar:\
$HBASE_HOME/lib/hbase-unsafe-4.1.12.jar:\
$HBASE_HOME/lib/protobuf-java-2.5.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-api-1.49.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-context-1.49.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-semconv-1.29.0-alpha.jar"

# spark.master                                   YARN is a master
# spark.history.fs.logDirectory                  must-have
# spark.eventLog.*                               write Spark logs to HDFS
# spark.yarn.jars                                use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris               HIVE support
# spark.hadoop.hive.metastore.sasl.enabled       enable SASL for HIVE
# spark.hadoop.hive.metastore.kerberos.principal Kerberos for HIVE
# spark.sql.hive.metastore.version               specify Metastore version for Hive
# spark.sql.hive.metastore.jars                  tell Hive to take JARs from this folder
# spark.kerberos.*                               Kerberos setup
# spark.history.kerberos.*                       Kerberos setup
# spark.*.extraClassPath                         HBASE support
cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                                     yarn
spark.history.fs.logDirectory                    hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                               hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled                           true
spark.yarn.jars                                  hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris                 thrift://$MASTER_HOST:9083
spark.hadoop.hive.metastore.sasl.enabled         true
spark.hadoop.hive.metastore.kerberos.principal   hive/$MASTER_HOST@MARIPOSA.COM
spark.sql.hive.metastore.version                 4.1.0
spark.sql.hive.metastore.jars                    $HIVE_HOME/lib/*
spark.kerberos.principal                         hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.kerberos.keytab                            $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.history.kerberos.enabled                   true
spark.history.kerberos.principal                 hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.history.kerberos.keytab                    $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.driver.extraClassPath                      $HBASE_HOME/conf:$HBASE_LIBS
spark.executor.extraClassPath                    $HBASE_HOME/conf:$HBASE_LIBS
EOF

# setup Hive
if [[ "$IS_MASTER" == "true" ]]; then
    cat <<EOF > $HIVE_HOME/conf/hive-site.xml
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:postgresql://localhost:5432/metastore_db</value>
        <description>JDBC path to Postgres metastore DB</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.postgresql.Driver</value>
        <description>JDBC Driver</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>hive</value>
        <description>Postgres user</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>$HIVE_DB_PASSWORD</value>
        <description>Postgres password</description>
    </property>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://$MASTER_HOST:9083</value>
        <description>IP address and port of the Hive Metastore service</description>
    </property>
    <property>
        <name>hive.execution.engine</name>
        <value>mr</value>
        <description>switch TEZ -> MapReduce</description>
    </property>

    <property>
        <name>hive.metastore.sasl.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.principal</name>
        <value>hive/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hive.server2.authentication</name>
        <value>KERBEROS</value>
    </property>
    <property>
        <name>hive.server2.authentication.kerberos.principal</name>
        <value>hive/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hive.server2.authentication.kerberos.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.groups</name>
        <value>*</value>
        <description></description>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.hosts</name>
        <value>*</value>
        <description></description>
    </property>
</configuration>
EOF
else      # for workers
    cat <<EOF > $HIVE_HOME/conf/hive-site.xml
<configuration>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://$MASTER_HOST:9083</value>
        <description>IP address and port of the Hive Metastore service</description>
    </property>
</configuration>
EOF
fi

# fix issue with 'remove deprecated packages attribute' by creating minimal log4j2 file
cat <<EOF > $HIVE_HOME/conf/hive-log4j2.properties
name = HiveLog4j2Configuration

appender.console.type = Console
appender.console.name = Console
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%t] %c{1}: %m%n

rootLogger.level = INFO
rootLogger.appenderRef.console.ref = Console
EOF


# ZOOKEEPER
# setup ZK for each node (ZK_ID must be a unique number for every node, e.g. 1,2,3)
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


# setup Apache Kafka
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
advertised.listeners=SASL_SSL://$MY_HOSTNAME:9092
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
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="kafka/$MY_HOSTNAME@MARIPOSA.COM";
};

KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="kafka/$MY_HOSTNAME@MARIPOSA.COM";
};
EOF

cat <<EOF > $KAFKA_HOME/config/sasl.properties
security.protocol=SASL_SSL
sasl.kerberos.service.name=kafka
ssl.truststore.location=$TRUSTSTORE
ssl.truststore.password=$JKS_PASSWORD
EOF


# setup HBase
# Fix: https://issues.apache.org/jira/browse/HDFS-16644
# TODO: refine
find $HBASE_HOME/lib -name "hadoop-*.jar" -delete
find $HBASE_HOME/lib -name "guava-*.jar" -delete
find $HBASE_HOME/lib -name "hbase-shaded-client-*.jar" -delete
cp -v $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar $HBASE_HOME/lib/

{
  echo "export HBASE_CLASSPATH_PREFIX=\"/opt/hbase/lib/mariposa-hbase-patch-2.5.13.jar\""
  echo "export HBASE_CLASSPATH=\"$HADOOP_CONF_DIR:$(hadoop classpath)\""
} >> $HBASE_HOME/conf/hbase-env.sh

cat <<EOF > $HBASE_HOME/conf/hbase-site.xml
<configuration>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
        <description>use HDFS instead of standalone local FS</description>
    </property>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://$MASTER_HOST:9000/hbase</value>
        <description>link to a Namenode</description>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>$MASTER_HOST,$WORKER_HOSTS</value>
        <description>Zookeeper full quorum list</description>
    </property>
    <property>
        <name>hbase.wal.provider</name>
        <value>filesystem</value>
        <description>fix java-17 Netty error: IllegalArgumentException: object is not an instance of declaring class</description>
    </property>

    <property>
        <name>hbase.security.authentication</name>
        <value>simple</value>
        <description>TODO: switch to kerberos</description>
    </property>
    <property>
        <name>hbase.security.authorization</name>
        <value>false</value>
        <description>TODO: switch to true</description>
    </property>
    <property>
        <name>hbase.ipc.client.fallback-to-simple-auth-allowed</name>
        <value>true</value>
        <description>TODO: switch to false or remove</description>
    </property>
    <property>
        <name>hbase.master.kerberos.principal</name>
        <value>hbase/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hbase.master.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hbase.regionserver.kerberos.principal</name>
        <value>hbase/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hbase.regionserver.keytab.file</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
</configuration>
EOF


# setup Hue
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "HUE_PASSWORD"
    cat <<EOF > $HUE_HOME/desktop/conf/hue.ini
[desktop]
  http_host=0.0.0.0
  http_port=8888
  secret_key=$HUE_PASSWORD
  auth_backend=kerberos

  [[database]]
    engine=django.db.backends.postgresql
    host=localhost
    port=5432
    user=hue
    password=$HUE_DB_PASSWORD
    name=hue_db

  [[kerberos]]
    hue_keytab=$KEYTABS_DIR/$MASTER_HOST.keytab
    hue_principal=hue/$MASTER_HOST@MARIPOSA.COM
    ccache_path=/var/run/hue/hue_krb5_ccache
    auth_enabled=true

[hadoop]
  [[hdfs_clusters]]
    [[[default]]]
      fs_defaultfs=hdfs://$MASTER_HOST:9000
      webhdfs_url=https://$MASTER_HOST:9871/webhdfs/v1
      security_enabled=true
      ssl_cert_ca_verify=false

  [[yarn_clusters]]
    [[[default]]]
      resourcemanager_host=$MASTER_HOST
      resourcemanager_port=8032

[beeswax]
  hive_server_host=$MASTER_HOST
  hive_server_port=10000
  hive_conf_dir=$HIVE_HOME/conf
  security_enabled=true
  auth_enabled=true
  auth_mechanism=GSSAPI
  sasl_mechanisms=GSSAPI
  hive_server_principal=hive/$MASTER_HOST@MARIPOSA.COM
  kerberos_principal=hive/$MASTER_HOST@MARIPOSA.COM
  use_sasl=true
EOF
fi


# opt: add a simple Spark DAG to Airflow
if [[ "$IS_MASTER" == "true" ]]; then
    cat <<EOF > $AIRFLOW_HOME/dags/spark_connection_test.py
import os
import glob
from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

# find the Spark examples JAR dynamically
SPARK_HOME = os.getenv('SPARK_HOME', '/opt/spark')
JAR_PATTERN = f"{SPARK_HOME}/examples/jars/spark-examples_*.jar"
found_jars = glob.glob(JAR_PATTERN)
EXAMPLES_JAR = found_jars[0] if found_jars else "NOT_FOUND"

MASTER_HOST = os.getenv('MASTER_HOST', '$MASTER_HOST')
KEYTABS_DIR = os.getenv('KEYTABS_DIR', '$KEYTABS_DIR')

with DAG(dag_id='spark_connection_test') as dag:
    submit_job = SparkSubmitOperator(
        task_id='submit_spark_pi',
        application=EXAMPLES_JAR,
        java_class='org.apache.spark.examples.SparkPi',
        application_args=['10'],
        principal=f'hadoop/{MASTER_HOST}@MARIPOSA.COM',
        keytab=f"{KEYTABS_DIR}/{MASTER_HOST}.keytab",
        name='airflow-spark-test-pi'
    )
EOF
fi


# =========================
# === starting services ===
# =========================

if [[ "$IS_MASTER" == "true" ]]; then
    # initialize Kerberos KDC Database
    if [ ! -f "/var/lib/krb5kdc/principal" ]; then
        log "First time run. Initializing Kerberos KDC..."
        check_env "KRB5_PASSWORD"
        sudo kdb5_util create -s -P "$KRB5_PASSWORD"
        
        # create Principals and their proper keytabs
        # -randkey means we don't want a human password; we'll use keytabs
        sudo kadmin.local -q "addprinc -randkey hadoop/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey zookeeper/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hbase/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey kafka/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hive/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hue/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey tommy@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM zookeeper/$MASTER_HOST@MARIPOSA.COM hbase/$MASTER_HOST@MARIPOSA.COM kafka/$MASTER_HOST@MARIPOSA.COM hive/$MASTER_HOST@MARIPOSA.COM hue/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/tommy.keytab tommy@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey hadoop/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey zookeeper/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey hbase/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey kafka/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k $KEYTABS_DIR/$worker.keytab hadoop/$worker@MARIPOSA.COM zookeeper/$worker@MARIPOSA.COM hbase/$worker@MARIPOSA.COM kafka/$worker@MARIPOSA.COM"
        done
        unset IFS

        # set keytabs to be read-only by hadoop
        sudo chown hadoop:hadoop $KEYTABS_DIR/*.keytab
        sudo chown tommy:hadoop  $KEYTABS_DIR/tommy.keytab
        sudo chmod 400 $KEYTABS_DIR/*.keytab
        
        log "Kerberos Principals and keytabs created."
    fi

    # start Kerberos services
    log "Starting Kerberos..."
    sudo service krb5-kdc start
    sudo service krb5-admin-server start
    until nc -zv $MASTER_HOST 88; do sleep 1; done

    # format HDFS
    if [ ! -f "$HADOOP_HOME/dfs/name/current/VERSION" ]; then
        log "First time run. Formatting Namenode"
        hdfs namenode -format -nonInteractive
    else
        info "OK: Namenode data detected"
    fi

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start namenode
    yarn --daemon start resourcemanager
    until nc -zv $MASTER_HOST 9000; do sleep 1; done

    # start Zookeeper
    log "Starting Zookeeper..."
    rm -vf $ZOOKEEPER_HOME/data/zookeeper_server.pid
    zkServer.sh start

    # create directories on HDFS
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM && klist
    hdfs dfs -mkdir -p /spark/logs        # must-have
    hdfs dfs -mkdir -p /user/hadoop       # opt, for HUE
    hdfs dfs -mkdir -p /user/hive/warehouse
    hdfs dfs -mkdir -p /tmp/hive
    hdfs dfs -chown hive:hive /user/hive/warehouse
    hdfs dfs -chown hive:hive /tmp/hive
    hdfs dfs -chmod 775 /user/hive/warehouse
    hdfs dfs -chmod 777 /tmp/hive

    # start Spark
    log "Starting Spark History Server..."
    start-history-server.sh

    # start Hive
    log "Starting Hive..."
    export PGPASSWORD="$HIVE_DB_PASSWORD"
    SCHEMA_EXISTS=$(psql --host localhost --username hive --dbname metastore_db --tuples-only --no-align --command "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'VERSION');")
    if [ "$SCHEMA_EXISTS" != "t" ]; then
        log "First time run. Initializing Hive Metastore..."
        schematool -initSchema -dbType postgres
    else
        info "OK: Hive Metastore detected"
    fi

    hive --service metastore   > "$HIVE_HOME/logs/metastore.log" 2>&1 &
    log "Wait for HDFS to exit Safe Mode..."
    hdfs dfsadmin -safemode wait                                        # must have
    hive --service hiveserver2 > "$HIVE_HOME/logs/hiveserver2.log" 2>&1 &

    # apache Airflow
    if [[ ${SKIP_AIRFLOW:-} != "true" ]]; then
        log "Starting Apache Airflow..."
        check_env "AIRFLOW_PASSWORD"

        export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://airflow:$AIRFLOW_DB_PASSWORD@localhost:5432/airflow_db"
        export AIRFLOW__API__PORT=8085                                  # port 8080 is taken by Spark
        export AIRFLOW__API__BASE_URL=http://localhost:8085             # used by DAG executor
        export AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_USERS="admin:admin,tommy:user"
        export AIRFLOW__API__EXPOSE_CONFIG="True"                       # show configs in "Admin -> Config" tab

        echo "{\"admin\":\"$AIRFLOW_PASSWORD\", \"tommy\":\"tommy\"}" > "$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated"

        airflowMetadata="/opt/airflow/metadata"
        if [ ! -f "$airflowMetadata/.init_done" ]; then
            log "First time run. Initializing Airflow database..."
            airflow db migrate
            touch "$airflowMetadata/.init_done"
            info "Airflow database initialized"
        else
            info "OK: Airflow database already initialized"
        fi

        log "Starting Apache Airflow components..."
        airflow api-server --port 8085 > "$AIRFLOW_HOME/logs/airflow-api-server.log" 2>&1 &

        # update secret key before running scheduler and dag-processor, so that they can pick up a new value
        # for some reason AIRFLOW__API__SECRET_KEY doesn't work => sed manually
        until [ -s "$AIRFLOW_HOME/airflow.cfg" ]; do sleep 1; done
        grep 'secret_key = ' $AIRFLOW_HOME/airflow.cfg
        sed -i 's/^secret_key = .*$/secret_key = d80678ac0f4fa9e278aa83e1fc72001c2ad91f1da8c77f6c7ca914a8095be758/g' $AIRFLOW_HOME/airflow.cfg
        grep 'secret_key = ' $AIRFLOW_HOME/airflow.cfg

        airflow scheduler     > "$AIRFLOW_HOME/logs/airflow-scheduler.log"     2>&1 &
        airflow dag-processor > "$AIRFLOW_HOME/logs/airflow-dag-processor.log" 2>&1 &
    else
        warn "SKIP_AIRFLOW is true => Airflow is not started"
    fi

    # HUE
    if [[ ${SKIP_HUE:-} != "true" ]]; then
        log "Starting HUE..."
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue migrate)        # ("cd" needed)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue kt_renewer > $HUE_HOME/logs/kt_renewer.log 2>&1 &)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue runserver 0.0.0.0:8888 > $HUE_HOME/logs/hue.log 2>&1 &)
    else
        warn "SKIP_HUE is true => HUE is not started"
    fi

    # opt: copy Spark libs to HDFS for better performance
    if ! hdfs dfs -test -e /spark/libs; then
        log "First time run. Uploading Spark JARs to HDFS... (it may take some time)..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    else
        info "OK: Spark JARs already loaded into HDFS"
    fi

    # start HBase with a new kinit
    log "Starting HBase Master..."
    hdfs dfs -mkdir /hbase && hdfs dfs -chown hbase:hadoop /hbase    # must-have
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hbase/$MASTER_HOST@MARIPOSA.COM && klist
    hbase-daemon.sh start master
else      # WORKERs
    # wait for KDC
    until nc -zv $MASTER_HOST 88; do sleep 1; done

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start datanode
    yarn --daemon start nodemanager

    # start Zookeeper
    log "Starting Zookeeper..."
    rm -vf $ZOOKEEPER_HOME/data/zookeeper_server.pid
    zkServer.sh start

    # start HBase
    sleep 15     # simple sync with master
    log "Starting HBase RegionServer..."
    kinit -kt $KEYTABS_DIR/$MY_HOSTNAME.keytab hbase/$MY_HOSTNAME@MARIPOSA.COM && klist
    hbase-daemon.sh start regionserver
fi

# start Kafka on all nodes
log "Starting Kafka Server..."
if [ ! -f "$KAFKA_HOME/data/meta.properties" ]; then
    log "First time run. Formatting Kafka storage"
    $KAFKA_HOME/bin/kafka-storage.sh format --cluster-id $KAFKA_CLUSTER_ID --config $KAFKA_HOME/config/server.properties
else
    info "OK: Kafka storage already formatted"
fi
kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties


# infinite loop
kinit -kt $KEYTABS_DIR/$(hostname).keytab hadoop/$(hostname)@MARIPOSA.COM && klist
sleep 3
log "Done!"
tail -f /dev/null
