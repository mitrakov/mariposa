#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-krb:1.0.0
set -euo pipefail  # exit on any error, undefined variable, or pipe failure

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # no colour
function debug() {
    message="$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] $1"
    echo -e "${PURPLE}${message}${NC}"
}
function log() {
    message="$(date +'%Y-%m-%d %H:%M:%S') [LOG]   $1"
    echo -e "${GREEN}${message}${NC}"
}
function info() {
    message="$(date +'%Y-%m-%d %H:%M:%S') [INFO]  $1"
    echo -e "${BLUE}${message}${NC}"
}
function warn() {
    message="$(date +'%Y-%m-%d %H:%M:%S') [WARN]  $1"
    echo -e "${YELLOW}${message}${NC}"
}
function error() {
    message="$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1"
    echo -e "${RED}${message}${NC}"
}
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
#check_env "HBASE_HOME"
#check_env "KAFKA_HOME"
#check_env "AIRFLOW_HOME"
#check_env "HUE_HOME"
check_env "HADOOP_CONF_DIR"
check_env "KEYTABS_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "JKS_PASSWORD"
#check_env "ZK_ID"




# DO NOT use _HOST in XML Configs! Use $MY_HOSTNAME (or $MASTER_HOST) instead!
MY_HOSTNAME=$(hostname)

# generate temp self-signed SSL certificate to enable SASL to auth data transfer protocol
# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
if [ ! -f "$HADOOP_CONF_DIR/certs/keystore.jks" ]; then
    log "Generate SSL certificates..."
    keytool -genkeypair \
        -alias hadoop \
        -keyalg RSA \
        -keysize 2048 \
        -validity 9999 \
        -keystore $HADOOP_CONF_DIR/certs/keystore.jks \
        -storepass $JKS_PASSWORD \
        -keypass $JKS_PASSWORD \
        -dname "CN=$MY_HOSTNAME" \
        -storetype PKCS12 \
        -noprompt
else
    info "OK. The keystore.jks found for $MY_HOSTNAME."
fi

# start Postgres
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "HIVE_DB_PASSWORD"

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

    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hive';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hive' user and 'metastore_db'..."
        sudo -u postgres psql --command "CREATE USER hive WITH PASSWORD '$HIVE_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE metastore_db OWNER hive;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE metastore_db TO hive;"
        log "PostgreSQL user 'hive' and database 'metastore_db' created."
    else
        info "OK: user 'hive' exists"
    fi
fi

log "Creating configs..."

# setup Kerberos
cat << EOF | sudo tee /etc/krb5.conf
[libdefaults]
    default_realm = MARIPOSA.COM

[realms]
    MARIPOSA.COM = {
        kdc = $MASTER_HOST
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
    <value>$HADOOP_CONF_DIR/certs/keystore.jks</value>
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
# spark.master                     YARN is a master
# spark.history.fs.logDirectory    must-have
# spark.eventLog.*                               write Spark logs to HDFS
# spark.yarn.jars                                use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris               HIVE support
# spark.hadoop.hive.metastore.sasl.enabled       enable SASL for HIVE
# spark.hadoop.hive.metastore.kerberos.principal Kerberos for HIVE
# spark.sql.hive.metastore.version               specify Metastore version for Hive
# spark.sql.hive.metastore.jars                  tell Hive to take JARs from this folder
# spark.kerberos.*                               Kerberos setup
# spark.history.kerberos.*                       Kerberos setup
cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                                   yarn
spark.history.fs.logDirectory                  hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                             hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled                         true
spark.yarn.jars                                hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris               thrift://$MASTER_HOST:9083
spark.hadoop.hive.metastore.sasl.enabled       true
spark.hadoop.hive.metastore.kerberos.principal hive/$MASTER_HOST@MARIPOSA.COM
spark.sql.hive.metastore.version               4.1.0
spark.sql.hive.metastore.jars                  $HIVE_HOME/lib/*
spark.kerberos.principal                       hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.kerberos.keytab                          $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.history.kerberos.enabled                 true
spark.history.kerberos.principal               hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.history.kerberos.keytab                  $KEYTABS_DIR/$MY_HOSTNAME.keytab
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
        <name>hive.metastore.sasl.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.principal</name>
        <value>hive/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.keytab.file</name>
        <value>$KEYTABS_DIR/hive.keytab</value>
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
        sudo kadmin.local -q "addprinc -randkey hive/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/hive.keytab hive/$MASTER_HOST@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey hadoop/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k $KEYTABS_DIR/$worker.keytab hadoop/$worker@MARIPOSA.COM"
        done
        unset IFS

        # set keytabs to be read-only by hadoop
        sudo chown hadoop:hadoop $KEYTABS_DIR/*.keytab
        sudo chmod 400 $KEYTABS_DIR/*.keytab
        
        log "Kerberos Principals and keytabs created."
    fi

    # start Kerberos services
    log "Starting Kerberos..."
    sudo service krb5-kdc start
    sudo service krb5-admin-server start

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
    until nc -zv $MASTER_HOST 9000; do
        debug "Waiting for NameNode RPC at $MASTER_HOST:9000..."
        sleep 2
    done

    # start Spark
    log "Waiting for HDFS to exit safe mode..."
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab $(whoami)/$MASTER_HOST@MARIPOSA.COM
    klist
    hdfs dfsadmin -safemode wait

    log "Starting Spark History Server..."
    hdfs dfs -mkdir -p /spark/logs        # must-have
    start-history-server.sh

    # start Hive Metastore (in bg)
    log "Starting Hive Metastore..."
    export PGPASSWORD="$HIVE_DB_PASSWORD"
    SCHEMA_EXISTS=$(psql --host localhost --username hive --dbname metastore_db --tuples-only --no-align --command "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'VERSION');")
    if [ "$SCHEMA_EXISTS" != "t" ]; then
        log "First time run. Initializing Hive Metastore..."
        schematool -initSchema -dbType postgres
    else
        info "OK: Hive Metastore detected"
    fi
    hive --service metastore &

    # opt: copy Spark libs to HDFS for better performance
    if ! hdfs dfs -test -e /spark/libs; then
        log "First time run. Uploading Spark JARs to HDFS... (it may take some time)..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    else
        info "OK: Spark JARs already loaded into HDFS"
    fi
else      # WORKERs
    until nc -zv $MASTER_HOST 88; do
      debug "Waiting for KDC at $MASTER_HOST:88..."
      sleep 4
    done

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start datanode
    yarn --daemon start nodemanager
fi

# infinite loop
sleep 1
log "Done!"
tail -f /dev/null
