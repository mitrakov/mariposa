#!/bin/bash
docker run --rm --name hey \
  --env MASTER_HOST=localhost \
  --env IS_MASTER=true \
  --env WORKER_HOSTS=localhost \
  --env HIVE_DB_PASSWORD=12345 \
  --volume ~/hadoop/test_master_data:/opt/hadoop/dfs/name \
  --volume ~/hadoop/test_datanode_data:/opt/hadoop/dfs/data \
  --volume ~/hadoop/test_postgres_data:/var/lib/postgresql/16/main \
  --publish 9870:9870 \
  --publish 8088:8088 \
  --publish 18080:18080 \
  --publish 16010:16010 \
  --publish 16020:16020 \
  --publish 4040:4040 \
  mitrakov/hadoop:1.0.0

# WARN util.NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
