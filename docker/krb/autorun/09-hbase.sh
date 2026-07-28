#!/usr/bin/env bash
# Apache HBase
set -euo pipefail
. utils.sh
. .env

check_env "KEYTABS_DIR"
check_env "HBASE_HOME"
check_env "HADOOP_HOME"
check_env "HADOOP_CONF_DIR"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "IS_MASTER"
check_file "$KEYTABS_DIR/$(hostname).keytab"


# Fix SASL issue (secured HBase only): https://issues.apache.org/jira/browse/HDFS-16644
find $HBASE_HOME/lib -name "hadoop-*.jar" -delete
find $HBASE_HOME/lib -name "guava-*.jar" -delete
find $HBASE_HOME/lib -name "hbase-shaded-client-*.jar" -delete
cp -v $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar $HBASE_HOME/lib/

{
  echo "export HBASE_CLASSPATH_PREFIX=\"/opt/hbase/lib/mariposa-hbase-patch-2.5.13.jar\""
  echo "export HBASE_CLASSPATH=\"$HADOOP_CONF_DIR:$(hadoop classpath)\""
} >> $HBASE_HOME/conf/hbase-env.sh

cat <<EOF > $HBASE_HOME/conf/hbase-site.xml
<configuration>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
        <description>use HDFS instead of standalone local FS</description>
    </property>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://$MASTER_HOST:9000/hbase</value>
        <description>link to a Namenode</description>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>$MASTER_HOST,$WORKER_HOSTS</value>
        <description>Zookeeper full quorum list</description>
    </property>
    <property>
        <name>hbase.wal.provider</name>
        <value>filesystem</value>
        <description>fix java-17 Netty error: IllegalArgumentException: object is not an instance of declaring class</description>
    </property>
    <property>
        <name>hbase.security.authentication</name>
        <value>simple</value>
        <description>TODO: switch to kerberos</description>
    </property>
    <property>
        <name>hbase.security.authorization</name>
        <value>false</value>
        <description>TODO: switch to true</description>
    </property>
    <property>
        <name>hbase.ipc.client.fallback-to-simple-auth-allowed</name>
        <value>true</value>
        <description>TODO: switch to false or remove</description>
    </property>
    <property>
        <name>hbase.master.kerberos.principal</name>
        <value>hbase/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hbase.master.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hbase.regionserver.kerberos.principal</name>
        <value>hbase/$(hostname)@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hbase.regionserver.keytab.file</name>
        <value>$KEYTABS_DIR/$(hostname).keytab</value>
    </property>
</configuration>
EOF


log "Starting HBase..."
if [[ "$IS_MASTER" == "true" ]]; then
    hdfs dfs -mkdir -p /hbase           # must-have
    hdfs dfs -chown hbase:hadoop /hbase
    hbase-daemon.sh start master
    hbase-daemon.sh start thrift        # for HUE
else
    hbase-daemon.sh start regionserver
fi
