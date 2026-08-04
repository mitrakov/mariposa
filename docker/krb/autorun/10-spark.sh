#!/usr/bin/env bash
# Apache Spark
set -euo pipefail
source utils.sh
source .env

check_env "KEYTABS_DIR"
check_env "MY_HOSTNAME"
check_env "SPARK_HOME"
check_env "HBASE_HOME"
check_env "HIVE_HOME"
check_env "MASTER_HOST"
check_file "$KEYTABS_DIR/$MY_HOSTNAME.keytab"


# spark.master                                   YARN is a master
# spark.history.fs.logDirectory                  must-have
# spark.eventLog.*                               write Spark logs to HDFS
# spark.yarn.jars                                use JARs directly from HDFS
# spark.hadoop.hive.metastore.uris               HIVE support
# spark.hadoop.hive.metastore.sasl.enabled       enable SASL for HIVE
# spark.hadoop.hive.metastore.kerberos.principal Kerberos for HIVE
# spark.sql.hive.metastore.version               specify Metastore version for Hive
# spark.sql.hive.metastore.jars                  tell Hive to take JARs from this folder
# spark.kerberos.*                               Kerberos setup
# spark.history.kerberos.*                       Kerberos setup
# spark.*.extraClassPath                         HBASE support

# TODO: check wildcards, e.g. lib/hbase-client-*.jar
HBASE_LIBS="$HBASE_HOME/lib/hbase-client-2.5.14.jar:\
$HBASE_HOME/lib/hbase-common-2.5.14.jar:\
$HBASE_HOME/lib/hbase-protocol-2.5.14.jar:\
$HBASE_HOME/lib/hbase-protocol-shaded-2.5.14.jar:\
$HBASE_HOME/lib/hbase-server-2.5.14.jar:\
$HBASE_HOME/lib/hbase-mapreduce-2.5.14.jar:\
$HBASE_HOME/lib/hbase-shaded-miscellaneous-4.1.13.jar:\
$HBASE_HOME/lib/hbase-shaded-protobuf-4.1.13.jar:\
$HBASE_HOME/lib/hbase-shaded-netty-4.1.13.jar:\
$HBASE_HOME/lib/hbase-shaded-gson-4.1.13.jar:\
$HBASE_HOME/lib/hbase-unsafe-4.1.13.jar:\
$HBASE_HOME/lib/protobuf-java-2.5.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-api-1.49.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-context-1.49.0.jar:\
$HBASE_HOME/lib/client-facing-thirdparty/opentelemetry-semconv-1.29.0-alpha.jar"

cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                                     yarn
spark.history.fs.logDirectory                    hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                               hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled                           true
spark.yarn.jars                                  hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris                 thrift://$MASTER_HOST:9083
spark.hadoop.hive.metastore.sasl.enabled         true
spark.hadoop.hive.metastore.kerberos.principal   hive/$MASTER_HOST@MARIPOSA.COM
spark.sql.hive.metastore.version                 4.1.0
spark.sql.hive.metastore.jars                    $HIVE_HOME/lib/*
spark.kerberos.principal                         hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.kerberos.keytab                            $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.history.kerberos.enabled                   true
spark.history.kerberos.principal                 hadoop/$MY_HOSTNAME@MARIPOSA.COM
spark.history.kerberos.keytab                    $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.driver.extraClassPath                      $HBASE_HOME/conf:$HBASE_LIBS
spark.executor.extraClassPath                    $HBASE_HOME/conf:$HBASE_LIBS
EOF


if [[ "$IS_MASTER" == "true" ]]; then
    log "Starting Spark History Server..."
    
    hdfs dfs -mkdir -p /spark/logs           # must-have
    start-history-server.sh

    # opt: copy Spark libs to HDFS for better performance
    if ! hdfs dfs -test -e /spark/libs; then
        log "First time run. Uploading Spark JARs to HDFS... (it may take some time)..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    else
        info "OK: Spark JARs already loaded into HDFS"
    fi
fi
