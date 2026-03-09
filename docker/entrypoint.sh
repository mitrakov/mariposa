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
        exit 5
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
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "HADOOP_CONF_DIR"

check_os
check_hostname
check_primary_ip
check_java

# start SSH daemon
sudo service ssh start

# minimal setup for HDFS
log "Creating configs..."
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
</configuration>
EOF

# setup replication factor && switch default "/tmp/hadoop-hadoop/dfs/name" to stable path
if [[ "$MASTER_HOST" == "localhost" ]] || [[ "$MASTER_HOST" == "127.0.0.1" ]] || [[ "$MASTER_HOST" == "$WORKER_HOSTS" ]]; then
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
# spark.master:                  YARN is a master
# spark.history.fs.logDirectory: must-have
# spark.eventLog.*:              optional, write Spark logs to HDFS
# spark.yarn.jars:               optional, use JARs directly from HDFS
cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                      yarn
spark.history.fs.logDirectory     hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled            true
spark.yarn.jars                   hdfs:///spark/libs/*.jar
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
    log "Starting services..."
    start-dfs.sh
    start-yarn.sh
    hdfs dfs -mkdir -p /spark/logs        # must-have
    start-history-server.sh

    # optional: copy Spark libs to HDFS
    if ! hdfs dfs -test -e /spark/libs; then
        log "Uploading Spark JARs to HDFS..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    fi
fi

# infinite loop
log "Done!"
tail -f /dev/null
