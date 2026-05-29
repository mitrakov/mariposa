#!/bin/bash

# 1. fix: secmanreference.conf: ctl.env.dev = "http://localhost:3000"
# 2. CtlClient.scala:138: if (true) return Either.right("{}");
# mvn package --projects openflow/openflow-datamarts/custom_blago_test_tcache --also-make -DskipTests && cp -v target/arkp-submit-jar-with-dependencies.jar ~/openblow/wms/; say hola

spark-submit \
  --class ru.sberbank.bigdata.cloud.arkp.etl.openflow.wf.RunSqlSP \
  --driver-java-options "-Dapp.ctl.url=http://localhost:3000 -Dapp.ctl.loading=$(date +%s) -Dapp.hdfs.file.path=/hadoop/a.sql" \
  arkp-submit-jar-with-dependencies.jar
}
