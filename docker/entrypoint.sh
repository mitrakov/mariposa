#!/usr/bin/env bash
set -euo pipefail  # exit on any error, undefined variable, or pipe failure

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # no colour
function log() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [LOG]   $1"
    echo -e "${GREEN}${message}${NC}"
}
function info() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $1"
    echo -e "${BLUE}${message}${NC}"
}
function warn() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $1"
    echo -e "${YELLOW}${message}${NC}"
}
function error() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${message}${NC}"
}
function check_env() {
    if [[ -z "${!1:-}" ]]; then
        error "Error: environment variable '$1' is not set or empty"
        exit 1
    else
        info "$1: ${!1}"
    fi
}
function check_os() {
    local result=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        result="MacOS $(sw_vers -productVersion) (Build: $(sw_vers -buildVersion))"
    elif [[ -f /etc/os-release ]]; then
        # linux distributions with /etc/os-release
        source /etc/os-release
        result="$ID $VERSION_ID ($PRETTY_NAME)"
    elif [[ -f /etc/redhat-release ]]; then
        # fallback for older RHEL systems without /etc/os-release
        result=$(cat /etc/redhat-release)
    else
        error "Unable to detect operating system"
        exit 1
    fi

    info "OS: $result"
}
function check_primary_ip() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use route and ifconfig
        primary_interface=$(route get default | grep interface | awk '{print $2}')
        ipv4_addr=$(ifconfig "$primary_interface" | grep 'inet ' | awk '{print $2}')
    else
        # Linux - use ip command
        primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)
        ipv4_addr=$(ip -4 addr show "$primary_interface" | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    info "Default IPv4 address: $ipv4_addr"
}
function check_hostname() {
    info "Hostname: $(hostname)"
}
function check_java() {
    if command -v java &> /dev/null; then
        java_version=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    
        if [[ -n "$java_version" ]]; then
            info "Java version: $java_version"
        else
            warn "Cannot detect Java version"
        fi
    else
        warn "'java' command not found"
    fi
}



# =====



check_env "JAVA_HOME"
check_env "HADOOP_HOME"
check_env "SPARK_HOME"
check_env "HIVE_HOME"
check_env "HBASE_HOME"
check_env "ZOOKEEPER_HOME"
check_env "KAFKA_HOME"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "ZK_ID"
check_env "HADOOP_CONF_DIR"

check_os
check_hostname
check_primary_ip
check_java

# start SSH daemon
log "Starting SSH..."
sudo service ssh start

# start Postgres (master only)
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "HIVE_DB_PASSWORD"

    log "Starting PostgreSQL..."
    PG_DATA_DIR="/var/lib/postgresql/16/main"

    sudo chown -R postgres:postgres /var/lib/postgresql/16
    if [ ! -s "$PG_DATA_DIR/PG_VERSION" ]; then
        log "First time run. Initializing PostgreSQL database..."
        sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D "$PG_DATA_DIR"        # initdb must be run as the postgres user
    else
        log "OK: Database exists in $PG_DATA_DIR"
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
        log "OK: user 'hive' exists"
    fi
fi

log "Creating configs..."

# minimal setup for HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
</configuration>
EOF

# setup replication factor && switch default "/tmp/hadoop-hadoop/dfs/name" to stable path
if [[ "$MASTER_HOST" == "localhost" ]] || [[ "$MASTER_HOST" == "127.0.0.1" ]]; then
    DFS_REPLICATION=1
else
    DFS_REPLICATION=2
fi
cat <<EOF > $HADOOP_CONF_DIR/hdfs-site.xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>$DFS_REPLICATION</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>$HADOOP_HOME/dfs/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>$HADOOP_HOME/dfs/data</value>
    </property>
</configuration>
EOF

# minimal setup for Yarn
cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
    </property>
</configuration>
EOF

# setup Apache Spark
# spark.master                     YARN is a master
# spark.history.fs.logDirectory    must-have
# spark.eventLog.*                 opt, write Spark logs to HDFS
# spark.yarn.jars                  opt, use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris opt, HIVE support
cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                       yarn
spark.history.fs.logDirectory      hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                 hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled             true
spark.yarn.jars                    hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris   thrift://$MASTER_HOST:9083
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

# setup HBase (HBASE_MANAGES_ZK=false is needed not to start ZK on its own)
export HBASE_MANAGES_ZK=false
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
        <name>hbase.zookeeper.property.clientPort</name>
        <value>2181</value>
    </property>
    <property>
      <name>hbase.wal.provider</name>
      <value>filesystem</value>
      <description>fix java-17 Netty error: IllegalArgumentException: object is not an instance of declaring class</description>
    </property>
</configuration>
EOF

# setup ZK for each node (ZK_ID must be a unique number for every node, e.g. 1,2,3)
echo "$ZK_ID" > $ZOOKEEPER_HOME/data/myid

cat <<EOF > $ZOOKEEPER_HOME/conf/zoo.cfg
tickTime=1000
initLimit=10
syncLimit=5
dataDir=$ZOOKEEPER_HOME/data
clientPort=2181

server.1=$MASTER_HOST:2888:3888
EOF

count=2     # "1" is already set for $MASTER_HOST
IFS=','
for worker in $WORKER_HOSTS; do
    echo "server.$count=$worker:2888:3888" >> $ZOOKEEPER_HOME/conf/zoo.cfg
    count=$((count + 1))
done
unset IFS

# setup Apache Kafka
MY_HOST=$(hostname)
ZK_QUORUM="$MASTER_HOST:2181"
IFS=','
for worker in $WORKER_HOSTS; do
    ZK_QUORUM="$ZK_QUORUM,$worker:2181"
done
unset IFS

cat <<EOF > $KAFKA_HOME/config/server.properties
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://$MY_HOST:9092
broker.id=$ZK_ID
zookeeper.connect=$ZK_QUORUM
EOF



# =====

# opt: disable log4j-slf4j-impl JARs that cause "SLF4J: Class path contains multiple SLF4J bindings."
find $HIVE_HOME/lib/ -name "log4j-slf4j-impl-*.jar" | while read -r jar; do
    sudo mv -v "$jar" "$jar.bak"
done
find $HBASE_HOME/lib/client-facing-thirdparty/ -name "log4j-slf4j-impl-*.jar" | while read -r jar; do
    sudo mv -v "$jar" "$jar.bak"
done

# ZK
log "Starting Zookeeper..."
zkServer.sh start


# Clean up stale Kafka registration in ZK (sleep 3 id to take some fresh air for ZK)
sleep 3
log "Checking for stale Kafka registration for Broker $ZK_ID..."
zkCli.sh -server $MASTER_HOST:2181 delete /brokers/ids/$ZK_ID || true
sleep 3

# Kafka
log "Starting Kafka Server..."
kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties

# master logic
if [[ "$IS_MASTER" == "true" ]]; then
    # parse worker hosts
    echo "$WORKER_HOSTS" | tr ',' '\n' > $HADOOP_CONF_DIR/workers

    # format HDFS
    if [ ! -f "$HADOOP_HOME/dfs/name/current/VERSION" ]; then
        log "First time run. Formatting Namenode"
        hdfs namenode -format -nonInteractive
    else
        log "OK: Namenode data detected."
    fi

    # start Hadoop/Spark
    log "Starting HDFS..."
    start-dfs.sh
    log "Starting YARN..."
    start-yarn.sh
    hdfs dfs -mkdir -p /spark/logs        # must-have
    log "Starting Spark History Server..."
    start-history-server.sh

    # start HBase
    log "Starting HBase..."
    start-hbase.sh

    # start Hive Metastore (in bg)
    log "Starting Hive Metastore..."
    export PGPASSWORD="$HIVE_DB_PASSWORD"
    SCHEMA_EXISTS=$(psql --host localhost --username hive --dbname metastore_db --tuples-only --no-align --command "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'VERSION');")
    if [ "$SCHEMA_EXISTS" != "t" ]; then
        log "First time run. Initializing Hive Metastore..."
        schematool -initSchema -dbType postgres
    else
        log "OK: Hive Metastore detected"
    fi
    hive --service metastore &

    # opt: copy Spark libs to HDFS for better performance
    if ! hdfs dfs -test -e /spark/libs; then
        log "First time run. Uploading Spark JARs to HDFS... (it may take some time)..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    else
        log "OK: Spark JARs already loaded into HDFS"
    fi
fi

# infinite loop
sleep 1
log "Done!"
tail -f /dev/null
