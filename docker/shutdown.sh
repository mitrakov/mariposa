#!/usr/bin/env bash
set -euo pipefail

# stop hbase
hbase-daemon.sh stop thrift
hbase-daemon.sh stop master

# stop Yarn apps
if nc -zv $MASTER_HOST 8032; then
  for app in $(yarn application -list -appStates RUNNING | grep -Po "application_\d+_\d+"); do
    yarn application -kill "$app"
  done
fi

# stop spark
stop-history-server.sh

# stop HDFS
hdfs --daemon stop namenode
yarn --daemon stop resourcemanager

# stop ZK
zkServer.sh stop

# system shutdown
sudo shutdown now
