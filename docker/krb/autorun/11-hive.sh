#!/usr/bin/env bash
# Apache Hive & Apache Tez
set -euo pipefail
. utils.sh
. .env

check_env "IS_MASTER"
check_env "HIVE_HOME"
check_env "TEZ_HOME"
check_env "MASTER_HOST"


# setup Hive
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "KEYTABS_DIR"
    check_env "HIVE_DB_PASSWORD"
    check_file "$KEYTABS_DIR/$MASTER_HOST.keytab"

    cat <<EOF > $HIVE_HOME/conf/hive-site.xml
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:postgresql://localhost:5432/metastore_db</value>
        <description>JDBC path to Postgres metastore DB</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.postgresql.Driver</value>
        <description>JDBC Driver</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>hive</value>
        <description>Postgres user</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>$HIVE_DB_PASSWORD</value>
        <description>Postgres password</description>
    </property>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://$MASTER_HOST:9083</value>
        <description>IP address and port of the Hive Metastore service</description>
    </property>
    <property>
        <name>hive.metastore.sasl.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.principal</name>
        <value>hive/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hive.server2.authentication</name>
        <value>KERBEROS</value>
    </property>
    <property>
        <name>hive.server2.authentication.kerberos.principal</name>
        <value>hive/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>hive.server2.authentication.kerberos.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
</configuration>
EOF
else      # for workers
    cat <<EOF > $HIVE_HOME/conf/hive-site.xml
<configuration>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://$MASTER_HOST:9083</value>
        <description>IP address and port of the Hive Metastore service</description>
    </property>
</configuration>
EOF
fi

# fix issue with 'remove deprecated packages attribute' by creating minimal log4j2 file
cat <<EOF > $HIVE_HOME/conf/hive-log4j2.properties
name = HiveLog4j2Configuration

appender.console.type = Console
appender.console.name = Console
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%t] %c{1}: %m%n

rootLogger.level = INFO
rootLogger.appenderRef.console.ref = Console
EOF

# setup Tez
cat <<EOF > $TEZ_HOME/conf/tez-site.xml
<configuration>
    <property>
        <name>tez.lib.uris</name>
        <value>\${fs.defaultFS}/apps/tez/tez.tar.gz</value>
        <description>Libs location on HDFS</description>
    </property>
    <property>
      <name>tez.am.launch.cmd-opts</name>
      <value>--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED</value>
      <description>Fix Java-17 issue</description>
    </property>
</configuration>
EOF
echo "export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:$TEZ_HOME/conf:$TEZ_HOME/*.jar:$TEZ_HOME/lib/protobuf*.jar" >> /opt/hadoop/etc/hadoop/hadoop-env.sh


log "Starting Hive..."
if [[ "$IS_MASTER" == "true" ]]; then
    hdfs dfs -mkdir -p  /user/hive/warehouse  # must-have
    hdfs dfs -mkdir -p  /tmp/hive             # must-have
    hdfs dfs -chmod 777 /tmp/hive             # must-have
    if ! hdfs dfs -test -e /apps/tez/tez.tar.gz; then
        hdfs dfs -mkdir -p /apps/tez
        hdfs dfs -put $TEZ_HOME/share/tez.tar.gz /apps/tez/
    fi

    export PGPASSWORD="$HIVE_DB_PASSWORD"
    SCHEMA_EXISTS=$(psql --host localhost --username hive --dbname metastore_db --tuples-only --no-align --command "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'VERSION');")
    if [ "$SCHEMA_EXISTS" != "t" ]; then
        log "First time run. Initializing Hive Metastore..."
        schematool -initSchema -dbType postgres
    else
        info "OK: Hive Metastore detected"
    fi

    rm --force $HIVE_HOME/conf/hiveserver2.pid              # in case of hard shutdown
    hive --service metastore   > "$HIVE_HOME/logs/metastore.log"   2>&1 &
    hive --service hiveserver2 > "$HIVE_HOME/logs/hiveserver2.log" 2>&1 &
fi
