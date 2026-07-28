#!/usr/bin/env bash

cd /home/hadoop/autorun/
sed -i "s|__ALL_HOSTS__|\"$MASTER_HOST\",\"${WORKER_HOSTS//,/\",\"}\"|g" ssu.json
java -jar ssu.jar ssu.json
