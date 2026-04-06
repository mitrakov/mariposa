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
        local lower_name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_name" == *"password"* ]]; then
            info "$1: **********"
        else
            info "$1: ${!1}"
        fi
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
check_env "SPARK_HOME"
check_env "HADOOP_HOME"
check_env "HIVE_HOME"
check_env "HBASE_HOME"
check_env "ZOOKEEPER_HOME"
check_env "KAFKA_HOME"
check_env "AIRFLOW_HOME"
check_env "HUE_HOME"
check_env "HADOOP_CONF_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "ZK_ID"

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

    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='airflow';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'airflow' user and 'airflow_db'..."
        sudo -u postgres psql --command "CREATE USER airflow WITH PASSWORD 'airflow_pass';"
        sudo -u postgres psql --command "CREATE DATABASE airflow_db OWNER airflow;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow;"
        log "PostgreSQL user 'airflow' and database 'airflow_db' created."
    else
        info "OK: user 'airflow' exists"
    fi
fi

log "Creating configs..."

# minimal setup for HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
        <description>give the datanodes address of the namenode</description>
    </property>
    <property>
      <name>hadoop.proxyuser.hue.hosts</name>
      <value>*</value>
      <description>add permissions for HUE</description>
    </property>
    <property>
      <name>hadoop.proxyuser.hue.groups</name>
      <value>*</value>
      <description>add permissions for HUE</description>
    </property>
</configuration>
EOF

# minimal HDFS setup
cat <<EOF > $HADOOP_CONF_DIR/hdfs-site.xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>2</value>
        <description>replication factor (default 3)</description>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>$HADOOP_HOME/dfs/name</value>
        <description>switch default "/tmp/hadoop-hadoop/dfs/name" to stable path</description>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>$HADOOP_HOME/dfs/data</value>
        <description>switch default "/tmp/hadoop-hadoop/dfs/data" to stable path</description>
    </property>
    <property>
        <name>dfs.webhdfs.enabled</name>
        <value>true</value>
        <description>Enable WebHDFS for HUE</description>
    </property>
</configuration>
EOF

# minimal setup for Yarn
cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
        <description>Tell Yarn the namenode address</description>
    </property>
</configuration>
EOF

# setup Apache Spark
# spark.master                     YARN is a master
# spark.history.fs.logDirectory    must-have
# spark.eventLog.*                 opt, write Spark logs to HDFS
# spark.yarn.jars                  opt, use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris opt, HIVE support
# spark.sql.hive.metastore.version opt, specify Metastore version for Hive
# spark.sql.hive.metastore.jars    opt, tell Hive to take JARs from this folder
# spark.*.extraClassPath           opt, HBASE support
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

cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                       yarn
spark.history.fs.logDirectory      hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                 hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled             true
spark.yarn.jars                    hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris   thrift://$MASTER_HOST:9083
spark.sql.hive.metastore.version   4.1.0
spark.sql.hive.metastore.jars      $HIVE_HOME/lib/*
spark.driver.extraClassPath        $HBASE_HOME/conf:$HBASE_LIBS
spark.executor.extraClassPath      $HBASE_HOME/conf:$HBASE_LIBS
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
# Role: every node acts as both a Broker and a Controller for high availability
process.roles=broker,controller
node.id=$ZK_ID
controller.quorum.voters=$VOTERS

# Network settings
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://$MY_HOST:9092
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT

# Log & Data
log.dirs=$KAFKA_HOME/data
num.partitions=3
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
EOF

# setup Hue
if [[ "$IS_MASTER" == "true" ]]; then
    cat <<EOF > $HUE_HOME/desktop/conf/hue.ini
[desktop]
  http_host=0.0.0.0
  http_port=8888
  secret_key=spark_hadoop_secret_key
  time_zone=UTC

[hadoop]
  [[hdfs_clusters]]
    [[[default]]]
      fs_defaultfs=hdfs://$MASTER_HOST:9000
      webhdfs_url=http://$MASTER_HOST:9870/webhdfs/v1

  [[yarn_clusters]]
    [[[default]]]
      resourcemanager_host=$MASTER_HOST
      resourcemanager_port=8032
      submit_to=True

[beeswax]
  hive_server_host=$MASTER_HOST
  hive_server_port=10000
EOF
fi

# opt: add a simple Spark DAG to Airflow
if [[ "$IS_MASTER" == "true" ]]; then
    cat <<EOF > $AIRFLOW_HOME/dags/spark_connection_test.py
import os
import glob
from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from datetime import datetime

# Helper to find the examples JAR dynamically
SPARK_HOME = os.getenv('SPARK_HOME', '/opt/spark')
JAR_PATTERN = f"{SPARK_HOME}/examples/jars/spark-examples_*.jar"
found_jars = glob.glob(JAR_PATTERN)
EXAMPLES_JAR = found_jars[0] if found_jars else "NOT_FOUND"

with DAG(dag_id='spark_connection_test') as dag:
    submit_job = SparkSubmitOperator(
        task_id='submit_spark_pi',
        application=EXAMPLES_JAR,
        java_class='org.apache.spark.examples.SparkPi',
        application_args=['10'],
        conf={
            "spark.master": "yarn",
            "spark.submit.deployMode": "client",
            "spark.executor.memory": "512m",
            "spark.driver.memory": "512m"
        },
        name='airflow-spark-test-pi'
    )
EOF
fi


# =========================
# === starting services ===
# =========================


# ZK
log "Starting Zookeeper..."
zkServer.sh start

# Kafka
log "Starting Kafka Server..."
sudo chown -R hadoop:hadoop $KAFKA_HOME/data     # fix issue when MacOS create volumes as "root"
# KRaft storage formatting
if [ ! -f "$KAFKA_HOME/data/meta.properties" ]; then
    log "First time run. Formatting Kafka storage"
    $KAFKA_HOME/bin/kafka-storage.sh format --cluster-id Mariposa20260406 --config $KAFKA_HOME/config/server.properties
else
    info "OK: Kafka storage already formatted"
fi
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
        info "OK: Namenode data detected"
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
        info "OK: Hive Metastore detected"
    fi
    hive --service metastore &

    # apache Airflow
    if [[ ${SKIP_AIRFLOW:-} != "true" ]]; then
        log "Starting Apache Airflow..."
        export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://airflow:airflow_pass@localhost:5432/airflow_db"
        export AIRFLOW__API__PORT=8085                                  # port 8080 is taken by Spark
        export AIRFLOW__API__BASE_URL=http://localhost:8085             # used by DAG executor
        export AIRFLOW__CORE__INTERNAL_API_URL=http://localhost:8085    # used by DAG updater

        airflow db migrate
        airflow standalone > $AIRFLOW_HOME/airflow.log 2>&1 &
    else
        warn "SKIP_AIRFLOW is true => Airflow is not started"
    fi

    # HUE
    if [[ ${SKIP_HUE:-} != "true" ]]; then
        log "Starting HUE..."
        # TODO: need to create volume for /opt/hue/build/env/lib/python3.11/site-packages/django/db/backends/sqlite3/base.py
        # simple "if (!migrated) then migrate" doesn't work
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue migrate)        # ("cd" needed)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue runserver 0.0.0.0:8888 > $HUE_HOME/logs/hue.log 2>&1 &)
        # opt: create a default user home for HUE to fix warnings on the web-page
        hdfs dfs -mkdir -p /user/hadoop
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

    # TODO: should be visible only first time
    warn "Airflow password:"
    cat $AIRFLOW_HOME/simple_auth_manager_passwords.json.generated || true
fi

# infinite loop
log "Done!"
tail -f /dev/null
