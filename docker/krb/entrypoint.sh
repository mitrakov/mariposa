#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-krb:1.0.0
set -euo pipefail

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
function debug() { echo -e "${PURPLE}$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] $1${NC}"; }
function log()   { echo -e "${GREEN}$(date +'%Y-%m-%d %H:%M:%S') [LOG]   $1${NC}"; }
function info()  { echo -e "${BLUE}$(date +'%Y-%m-%d %H:%M:%S') [INFO]  $1${NC}"; }
function warn()  { echo -e "${YELLOW}$(date +'%Y-%m-%d %H:%M:%S') [WARN]  $1${NC}"; }
function error() { echo -e "${RED}$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1${NC}"; }
function check_env() {
    if [[ -z "${!1:-}" ]]; then
        error "Error: environment variable '$1' is not set or empty"
        exit 1
    else
        local lower_name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_name" == *"password"* ]]; then
            info "$1: **********"
        else
            info "$1: ${!1}"
        fi
    fi
}


# DO NOT use _HOST in XML Configs! Use $MY_HOSTNAME (or $MASTER_HOST) instead!
MY_HOSTNAME=$(hostname)

# generate temp self-signed SSL certificate to enable SASL to auth data transfer protocol
# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
MY_KEYSTORE="$HADOOP_CONF_DIR/certs/$MY_HOSTNAME.keystore.jks"
TRUSTSTORE="$HADOOP_CONF_DIR/certs/truststore.jks"

if [ ! -f "$MY_KEYSTORE" ]; then
    log "Generating SSL for $MY_HOSTNAME..."

    # 1. Create node-specific keystore
    keytool -genkeypair -alias "$MY_HOSTNAME" -keyalg RSA -validity 9999 \
      -keystore "$MY_KEYSTORE" \
      -storepass "$JKS_PASSWORD" -keypass "$JKS_PASSWORD" \
      -dname "CN=$MY_HOSTNAME" -ext "SAN=dns:$MY_HOSTNAME" \
      -storetype PKCS12 -noprompt

    # 2. Export this node's certificate
    keytool -export -alias "$MY_HOSTNAME" \
      -file $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer \
      -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD"

    # 3. Import into the SHARED truststore
    sleep $ZK_ID    # must-have to avoid race-conditions!
    keytool -import -alias "$MY_HOSTNAME" \
      -file $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer \
      -keystore "$TRUSTSTORE" \
      -storepass "$JKS_PASSWORD" -noprompt

    rm -vf $HADOOP_CONF_DIR/certs/$MY_HOSTNAME.cer
    info "SSL certificates stored in $MY_KEYSTORE"
else
    info "OK: Keystore already exists: $MY_KEYSTORE"
fi


# start Postgres
if [[ "$IS_MASTER" == "true" ]]; then
    log "Starting PostgreSQL..."
    PG_DATA_DIR="/var/lib/postgresql/16/main"

    sudo chown -R postgres:postgres /var/lib/postgresql/16
    if [ ! -s "$PG_DATA_DIR/PG_VERSION" ]; then
        log "First time run. Initializing PostgreSQL database..."
        sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D "$PG_DATA_DIR"        # initdb must be run as the postgres user
    else
        info "OK: Database exists in $PG_DATA_DIR"
    fi
    sudo service postgresql start

    check_env "HIVE_DB_PASSWORD"
    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hive';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hive' user and 'metastore_db'..."
        sudo -u postgres psql --command "CREATE USER hive WITH PASSWORD '$HIVE_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE metastore_db OWNER hive;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE metastore_db TO hive;"
        info "PostgreSQL user 'hive' and database 'metastore_db' created"
    else
        info "OK: user 'hive' exists"
    fi

    check_env "HUE_DB_PASSWORD"
    USER_EXISTS=$(sudo -u postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hue';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hue' user and 'hue_db'..."
        sudo -u postgres psql --command "CREATE USER hue WITH PASSWORD '$HUE_DB_PASSWORD';"
        sudo -u postgres psql --command "CREATE DATABASE hue_db OWNER hue;"
        sudo -u postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE hue_db TO hue;"
        log "PostgreSQL user 'hue' and database 'hue_db' created."
    else
        info "OK: user 'hue' exists"
    fi
fi

log "Creating configs..."

# setup Kerberos
cat << EOF | sudo tee /etc/krb5.conf
[libdefaults]
    default_realm = MARIPOSA.COM
    ticket_lifetime = 24h
    renew_lifetime = 7d

[realms]
    MARIPOSA.COM = {
        kdc = $MASTER_HOST
    }
EOF

# for HUE to renew TGT
cat << EOF | sudo tee /etc/krb5kdc/kdc.conf
[realms]
    MARIPOSA.COM = {
        max_life = 24h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF

# create simple kadm5.acl to avoid startup errors
echo "*/admin@MARIPOSA.COM *" | sudo tee /etc/krb5kdc/kadm5.acl

# minimal setup for HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
    </property>
    <property>
        <name>hadoop.security.authentication</name>
        <value>kerberos</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.groups</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.hosts</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.groups</name>
        <value>*</value>
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.hosts</name>
        <value>*</value>
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
    </property>
</configuration>
EOF



# minimal HDFS setup
cat <<EOF > $HADOOP_CONF_DIR/hdfs-site.xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>2</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>$HADOOP_HOME/dfs/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>$HADOOP_HOME/dfs/data</value>
    </property>
    <property>
        <name>dfs.namenode.kerberos.principal</name>
        <value>hadoop/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>hadoop/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.datanode.keytab.file</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
    <property>
        <name>dfs.data.transfer.protection</name>
        <value>authentication</value>
    </property>
    <property>
        <name>dfs.datanode.address</name>
        <value>0.0.0.0:10019</value>
        <description>https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode</description>
    </property>
    <property>
        <name>dfs.http.policy</name>
        <value>HTTPS_ONLY</value>
        <description>https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode</description>
    </property>
    <property>
        <name>dfs.block.access.token.enable</name>
        <value>true</value>
        <description>FIX: Security is enabled but block access tokens aren't enabled</description>
    </property>
</configuration>
EOF

# Kerberos setup for Yarn
cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
    </property>
    <property>
        <name>yarn.resourcemanager.principal</name>
        <value>hadoop/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>yarn.nodemanager.principal</name>
        <value>hadoop/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.nodemanager.keytab</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
</configuration>
EOF

# this is necessary for SASL data-transfer protocol to enable https
cat <<EOF > $HADOOP_CONF_DIR/ssl-server.xml
<configuration>
  <property>
    <name>ssl.server.keystore.location</name>
    <value>$MY_KEYSTORE</value>
  </property>
  <property>
    <name>ssl.server.keystore.password</name>
    <value>$JKS_PASSWORD</value>
  </property>
  <property>
    <name>ssl.server.keystore.keypassword</name>
    <value>$JKS_PASSWORD</value>
  </property>
</configuration>
EOF



# setup Hive
if [[ "$IS_MASTER" == "true" ]]; then
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
        <name>hive.execution.engine</name>
        <value>mr</value>
        <description>switch TEZ -> MapReduce</description>
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
    <property>
        <name>hadoop.proxyuser.hue.groups</name>
        <value>*</value>
        <description></description>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.hosts</name>
        <value>*</value>
        <description></description>
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


# setup Hue
cp -v /opt/hive/conf/hive-site.xml /opt/hue/
cp -v /opt/hive/conf/hive-site.xml /opt/hue/desktop/
cp -v /opt/hive/conf/hive-site.xml /opt/hue/desktop/conf/
if [[ "$IS_MASTER" == "true" ]]; then
    check_env "HUE_PASSWORD"
    cat <<EOF > $HUE_HOME/desktop/conf/hue.ini
[desktop]
  http_host=0.0.0.0
  http_port=8888
  secret_key=$HUE_PASSWORD
  auth_backend=kerberos

  [[database]]
    engine=django.db.backends.postgresql
    host=localhost
    port=5432
    user=hue
    password=$HUE_DB_PASSWORD
    name=hue_db

  [[kerberos]]
    hue_keytab=$KEYTABS_DIR/$MASTER_HOST.keytab
    hue_principal=hue/$MASTER_HOST@MARIPOSA.COM
    ccache_path=/var/run/hue/hue_krb5_ccache
    auth_enabled=true

[hadoop]
  [[hdfs_clusters]]
    [[[default]]]
      fs_defaultfs=hdfs://$MASTER_HOST:9000
      webhdfs_url=https://$MASTER_HOST:9871/webhdfs/v1
      security_enabled=true
      ssl_cert_ca_verify=false

  [[yarn_clusters]]
    [[[default]]]
      resourcemanager_host=$MASTER_HOST
      resourcemanager_port=8032

[beeswax]
  hive_server_host=$MASTER_HOST
  hive_server_port=10000
  hive_conf_dir=$HIVE_HOME/conf
  security_enabled=true
  auth_enabled=true
  auth_mechanism=GSSAPI
  sasl_mechanisms=GSSAPI
  hive_server_principal=hive2/$MASTER_HOST@MARIPOSA.COM
  kerberos_principal=hive3/$MASTER_HOST@MARIPOSA.COM
  use_sasl=true
EOF
fi



if [[ "$IS_MASTER" == "true" ]]; then
    # initialize Kerberos KDC Database
    if [ ! -f "/var/lib/krb5kdc/principal" ]; then
        log "First time run. Initializing Kerberos KDC..."
        check_env "KRB5_PASSWORD"
        sudo kdb5_util create -s -P "$KRB5_PASSWORD"
        
        # create Principals and their proper keytabs
        # -randkey means we don't want a human password; we'll use keytabs
        sudo kadmin.local -q "addprinc -randkey hadoop/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey zookeeper/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hbase/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey kafka/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hive/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey hue/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey tommy@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM zookeeper/$MASTER_HOST@MARIPOSA.COM hbase/$MASTER_HOST@MARIPOSA.COM kafka/$MASTER_HOST@MARIPOSA.COM hive/$MASTER_HOST@MARIPOSA.COM hue/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/tommy.keytab tommy@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey hadoop/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey zookeeper/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey hbase/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey kafka/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k $KEYTABS_DIR/$worker.keytab hadoop/$worker@MARIPOSA.COM zookeeper/$worker@MARIPOSA.COM hbase/$worker@MARIPOSA.COM kafka/$worker@MARIPOSA.COM"
        done
        unset IFS

        # set keytabs to be read-only by hadoop
        sudo chown hadoop:hadoop $KEYTABS_DIR/*.keytab
        sudo chown tommy:hadoop  $KEYTABS_DIR/tommy.keytab
        sudo chmod 400 $KEYTABS_DIR/*.keytab
        
        log "Kerberos Principals and keytabs created."
    fi

    # start Kerberos services
    log "Starting Kerberos..."
    sudo service krb5-kdc start
    sudo service krb5-admin-server start
    until nc -zv $MASTER_HOST 88; do sleep 1; done

    # format HDFS
    if [ ! -f "$HADOOP_HOME/dfs/name/current/VERSION" ]; then
        log "First time run. Formatting Namenode"
        hdfs namenode -format -nonInteractive
    else
        info "OK: Namenode data detected"
    fi

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start namenode
    yarn --daemon start resourcemanager
    until nc -zv $MASTER_HOST 9000; do sleep 1; done

    # create directories on HDFS
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM && klist
    hdfs dfs -mkdir -p /user/hadoop       # opt, for HUE
    hdfs dfs -mkdir -p /user/hive/warehouse
    hdfs dfs -mkdir -p /tmp/hive
    hdfs dfs -chown hive:hive /user/hive/warehouse
    hdfs dfs -chown hive:hive /tmp/hive
    hdfs dfs -chmod 775 /user/hive/warehouse
    hdfs dfs -chmod 777 /tmp/hive

    # start Hive
    log "Starting Hive..."
    export PGPASSWORD="$HIVE_DB_PASSWORD"
    SCHEMA_EXISTS=$(psql --host localhost --username hive --dbname metastore_db --tuples-only --no-align --command "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'VERSION');")
    if [ "$SCHEMA_EXISTS" != "t" ]; then
        log "First time run. Initializing Hive Metastore..."
        schematool -initSchema -dbType postgres
    else
        info "OK: Hive Metastore detected"
    fi

    hive --service metastore   > "$HIVE_HOME/logs/metastore.log" 2>&1 &
    log "Wait for HDFS to exit Safe Mode..."
    hdfs dfsadmin -safemode wait                                        # must have
    hive --service hiveserver2 > "$HIVE_HOME/logs/hiveserver2.log" 2>&1 &

    # HUE
    if [[ ${SKIP_HUE:-} != "true" ]]; then
        log "Starting HUE..."

        # todo: must-have: move to dockerfile
        sudo mkdir -p /var/run/hue
        sudo chown hadoop:hadoop /var/run/hue
        sudo chmod 777 /var/run/hue

        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue migrate)        # ("cd" needed)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue kt_renewer > $HUE_HOME/logs/kt_renewer.log 2>&1 &)
        
        #log "tail -f /dev/null"
        #tail -f /dev/null       # GEMINI, let's start debugging from here!
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue runserver 0.0.0.0:8888 > $HUE_HOME/logs/hue.log 2>&1 &)
    else
        warn "SKIP_HUE is true => HUE is not started"
    fi
else      # WORKERs
    # wait for KDC
    until nc -zv $MASTER_HOST 88; do sleep 1; done

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start datanode
    yarn --daemon start nodemanager
fi


# infinite loop
kinit -kt $KEYTABS_DIR/$(hostname).keytab hadoop/$(hostname)@MARIPOSA.COM && klist
log "Done!"
tail -f /dev/null
