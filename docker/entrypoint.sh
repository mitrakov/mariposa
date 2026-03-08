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
        exit 5
    else
        info "$1: ${!1}"
    fi
}

# =====
DFS_REPLICATION=${DFS_REPLICATION:-1}

check_env "JAVA_HOME"
check_env "HADOOP_HOME"
check_env "SPARK_HOME"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "HADOOP_CONF_DIR"
check_env "DFS_REPLICATION"

# start SSH daemon
sudo service ssh start

# setup data dirs for Docker volumes (must be in .sh, not in dockerfile)
mkdir -p $HADOOP_HOME/dfs && sudo chown -R hadoop:hadoop $HADOOP_HOME/dfs

# minimal setup for HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
</configuration>
EOF

# switch default "/tmp/hadoop-hadoop/dfs/name" to normal path
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
# spark.master:                  YARN is a master
# spark.yarn.jars:               use JARs directly from HDFS
# spark.history.fs.logDirectory: must-have
# spark.eventLog.*:              optional, write Spark logs to HDFS
cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                      yarn
spark.yarn.jars                   hdfs:///spark/libs/*.jar
spark.history.fs.logDirectory     hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled            true
EOF

# master logic
if [[ "$IS_MASTER" == "1" ]] || [[ "$IS_MASTER" == "true" ]]; then
    # parse worker hosts
    check_env "WORKER_HOSTS"
    echo "$WORKER_HOSTS" | tr ',' '\n' > $HADOOP_CONF_DIR/workers

    # format HDFS
    if [ ! -f "$HADOOP_HOME/dfs/name/current/VERSION" ]; then
        log "FIRST TIME run. Formatting Namenode"
        hdfs namenode -format -nonInteractive
    else
        log "Persistent volume detected: skipping format"
    fi

    # start Hadoop/Spark
    start-dfs.sh
    start-yarn.sh
    hdfs dfs -mkdir -p /spark/logs        # must-have
    start-history-server.sh

    # copy Spark libs to HDFS
    if ! hdfs dfs -test -e /spark/libs; then
        log "Uploading Spark JARs to HDFS..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    fi
fi

# infinite loop
tail -f /dev/null
