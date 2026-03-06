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


check_env "JAVA_HOME"
check_env "HADOOP_HOME"
check_env "MASTER_HOST"
check_env "IS_MASTER"

# start SSH daemon
sudo service ssh start

# main core-site.xml
cat <<EOF > $HADOOP_HOME/etc/hadoop/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
</configuration>
EOF

# the MapReduce/YARN config (needed for multi-node)
cat <<EOF > $HADOOP_HOME/etc/hadoop/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
    </property>
</configuration>
EOF

# master logic
if [[ "$IS_MASTER" == "1" ]] || [[ "$IS_MASTER" == "yes" ]]; then
    check_env "WORKER_HOSTS"
    echo "$WORKER_HOSTS" | tr ',' '\n' > $HADOOP_HOME/etc/hadoop/workers

    if [ ! -d "/tmp/hadoop-hadoop/dfs/name" ]; then
        hdfs namenode -format -force
    fi

    start-dfs.sh
    start-yarn.sh
fi

# infinite loop
tail -f /dev/null
