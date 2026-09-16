#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/flink-dev
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
check_env "HADOOP_HOME"
check_env "HADOOP_CONF_DIR"
check_env "FLINK_HOME"



# start SSH daemon
log "Starting SSH..."
sudo service ssh start



# HDFS
log "Creating Hadoop configs..."
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
        <description>give the datanodes address of the namenode</description>
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
</configuration>
EOF



# setup Apache Flink
log "Creating Flink configs..."

cat <<EOF > $FLINK_HOME/conf/config.yaml
target.local-space.dir: /tmp/flink

state:
  backend:
    type: rocksdb
  checkpoints:
    dir: hdfs://$MASTER_HOST:9000/flink/checkpoints
  savepoints:
    dir: hdfs://$MASTER_HOST:9000/flink/savepoints

jobmanager:
  execution:
    failover-strategy: region
  memory:
    process.size: 1600m

taskmanager:
  memory:
    process.size: 1728m
  numberOfTaskSlots: 2

parallelism:
  default: 2
EOF

echo "$MASTER_HOST:8081" > $FLINK_HOME/conf/masters
echo "$WORKER_HOSTS" | tr ',' '\n' > $FLINK_HOME/conf/workers



# =========================
# === starting services ===
# =========================

if [[ "$(hostname)" == "$MASTER_HOST" ]]; then
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

    # start Flink
    export HADOOP_CLASSPATH=$(hadoop classpath)     # must-have
    check_env "HADOOP_CLASSPATH"
    log "Starting Flink Session on YARN..."
    
    # -d = daemon; -jm = JobManager memory; -tm = TaskManager memory; -s = task slots per TaskManager
    yarn-session.sh -d -jm 1024m -tm 1024m -s 2 -nm "Flink-Mariposa"
fi


# infinite loop
log "Done!"
tail -f /dev/null
