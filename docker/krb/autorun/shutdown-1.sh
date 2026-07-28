#!/usr/bin/env bash
# graceful shutdown
set -euo pipefail
. utils.sh

check_env "IS_MASTER"
check_env "MASTER_HOST"


if [[ "$IS_MASTER" == "true" ]]; then

    # stop HBase
    hbase-daemon.sh stop thrift
    hbase-daemon.sh stop master

    # stop Yarn apps
    if nc -zv $MASTER_HOST 8032; then
        for app in $(yarn application -list -appStates RUNNING | grep -Po "application_\d+_\d+"); do
            yarn application -kill "$app"
        done
    fi

    # stop Spark
    stop-history-server.sh

    # stop HDFS
    hdfs --daemon stop namenode
    yarn --daemon stop resourcemanager

    # stop Zookeeper
    zkServer.sh stop
else
    # stop HBase
    hbase-daemon.sh stop regionserver

    # stop HDFS
    hdfs --daemon stop datanode
    yarn --daemon stop nodemanager
fi
