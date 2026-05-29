#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-dev:1.0.0
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
check_env "HBASE_HOME"
check_env "TEZ_HOME"
check_env "ZOOKEEPER_HOME"
check_env "KAFKA_HOME"
check_env "AIRFLOW_HOME"
check_env "HUE_HOME"
check_env "HADOOP_CONF_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "ZK_ID"
check_env "KAFKA_CLUSTER_ID"


MY_HOSTNAME=$(hostname)


# start SSH daemon
log "Starting SSH..."
sudo service ssh start


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
        log "PostgreSQL user 'hive' and database 'metastore_db' created."
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
        log "PostgreSQL user 'airflow' and database 'airflow_db' created."
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


# HDFS
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
    <property>
        <name>hadoop.proxyuser.hadoop.hosts</name>
        <value>*</value>
        <description>Hive FIX: User hadoop is not allowed to perform this API call</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hadoop.groups</name>
        <value>*</value>
        <description>Hive FIX: User hadoop is not allowed to perform this API call</description>
    </property>
</configuration>
EOF

cat <<EOF > $HADOOP_CONF_DIR/mapred-site.xml
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
    <description>Hive/Tez FIX: InvalidInputException: Input path does not exist: file:/tmp/hadoop/guid/hive_...7923819630025608960-1/dummy_path</description>
  </property>
</configuration>
EOF

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
</configuration>
EOF

cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
        <description>Tell Yarn the namenode address</description>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
        <description>Needed for Tez</description>
    </property>
</configuration>
EOF


# setup Apache Spark
# spark.master                     YARN is a master
# spark.history.fs.logDirectory    must-have
# spark.eventLog.*                 write Spark logs to HDFS
# spark.yarn.jars                  use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris HIVE support
# spark.sql.hive.metastore.version specify Metastore version for Hive
# spark.sql.hive.metastore.jars    tell Hive to take JARs from this folder
# spark.*.extraClassPath           HBASE support
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


# setup HBase (HBASE_MANAGES_ZK=false is needed not to start ZK on its own)
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
</configuration>
EOF


# ZOOKEEPER
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
advertised.listeners=PLAINTEXT://$MY_HOSTNAME:9092
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT

# Log & Data
log.dirs=$KAFKA_HOME/data
num.partitions=3
offsets.topic.replication.factor=3
EOF


# setup Hue
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "HUE_PASSWORD"
    cat <<EOF > $HUE_HOME/desktop/conf/hue.ini
[desktop]
  http_host=0.0.0.0
  http_port=8888
  secret_key=$HUE_PASSWORD

  [[database]]
    engine=django.db.backends.postgresql
    host=localhost
    port=5432
    user=hue
    password=$HUE_DB_PASSWORD
    name=hue_db

[hadoop]
  [[hdfs_clusters]]
    [[[default]]]
      fs_defaultfs=hdfs://$MASTER_HOST:9000
      webhdfs_url=http://$MASTER_HOST:9870/webhdfs/v1

  [[yarn_clusters]]
    [[[default]]]
      resourcemanager_host=$MASTER_HOST
      resourcemanager_port=8032

[beeswax]
  hive_server_host=$MASTER_HOST
  hive_server_port=10000
EOF
fi


# setup Tez
cat <<EOF > $TEZ_HOME/conf/tez-site.xml
<configuration>
    <property>
        <name>tez.lib.uris</name>
        <value>\${fs.defaultFS}/apps/tez/tez.tar.gz</value>
        <description>Libs location on HDFS</description>
    </property>
    <property>
      <name>tez.am.launch.cmd-opts</name>
      <value>--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED</value>
      <description>Fix Java-17 issue</description>
    </property>
</configuration>
EOF
echo "export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:$TEZ_HOME/conf:$TEZ_HOME/*.jar:$TEZ_HOME/lib/protobuf*.jar" >> /opt/hadoop/etc/hadoop/hadoop-env.sh


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

with DAG(dag_id='spark_connection_test') as dag:
    submit_job = SparkSubmitOperator(
        task_id='submit_spark_pi',
        application=EXAMPLES_JAR,
        java_class='org.apache.spark.examples.SparkPi',
        application_args=['10'],
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
# KRaft storage formatting
if [ ! -f "$KAFKA_HOME/data/meta.properties" ]; then
    log "First time run. Formatting Kafka storage"
    $KAFKA_HOME/bin/kafka-storage.sh format --cluster-id $KAFKA_CLUSTER_ID --config $KAFKA_HOME/config/server.properties
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

    # tez
    if ! hdfs dfs -test -e /apps/tez/tez.tar.gz; then
        hdfs dfs -mkdir -p /apps/tez
        hdfs dfs -put $TEZ_HOME/share/tez.tar.gz /apps/tez/
    fi

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
        export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://airflow:$AIRFLOW_DB_PASSWORD@localhost:5432/airflow_db"
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

    info "Airflow password:"
    cat $AIRFLOW_HOME/simple_auth_manager_passwords.json.generated || true
fi


# infinite loop
log "Done!"
tail -f /dev/null
