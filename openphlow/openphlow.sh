#!/usr/bin/env bash
# openphlow.sh for image: mitrakov/hadoop-krb:1.0.2
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



# checks
check_env "JAVA_HOME"
check_env "SPARK_HOME"
check_env "HADOOP_HOME"
check_env "HIVE_HOME"
check_env "HBASE_HOME"
check_env "TEZ_HOME"
check_env "ZOOKEEPER_HOME"
check_env "KAFKA_HOME"
check_env "HUE_HOME"
check_env "VAULT_HOME"
check_env "HADOOP_CONF_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_env "ZK_ID"
check_env "KEYTABS_DIR"
check_env "CERTS_DIR"
check_env "KAFKA_OPTS"


# DO NOT use _HOST in XML Configs! Use $MY_HOSTNAME (or $MASTER_HOST) instead!
MY_HOSTNAME=$(hostname)
export VAULT_ADDR=http://$MASTER_HOST:8200


# setup up HashiCorp Vault
if [[ "$IS_MASTER" == "true" ]]; then
    # create main config
    cat << EOF | sudo tee $VAULT_HOME/vault.hcl
storage "file" {
  path = "$VAULT_HOME/data"
}

listener "tcp" {
  address     = "$MASTER_HOST:8200"
  tls_disable = "true"
}
EOF
    # start HashiCorp Vault (as sudo to avoid error: "mlock syscall is not available" on real Ubuntu)
    log "Starting Vault..."
    sudo $VAULT_HOME/vault server --config=$VAULT_HOME/vault.hcl > $VAULT_HOME/vault.log 2>&1 &
    until nc -zv $MASTER_HOST 8200; do sleep 1; done

    # initialization Logic
    if [ ! -f "$VAULT_HOME/data/initialized" ]; then
        log "First time run. Initializing Vault..."

        # init
        INIT_INFO=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

        # get root toke for first time usage
        export VAULT_TOKEN=$(echo "$INIT_INFO" | jq --raw-output '.root_token')

        # store the unseal.key
        echo "$INIT_INFO" | jq --raw-output '.unseal_keys_b64[0]' > $VAULT_HOME/data/unseal.key
        chmod 400 $VAULT_HOME/data/unseal.key

        # unseal the vault
        vault operator unseal "$(cat $VAULT_HOME/data/unseal.key)"
        # enable approle auth method
        vault auth enable approle
        # enable kv engine
        vault secrets enable -path=secret kv-v2
        # define policy
        vault policy write hadoop-policy - <<EOF
path "pki/sign/secman" {
  capabilities = ["update"]
}
path "secret/data/hadoop/postgres" {
  capabilities = ["read"]
}
path "secret/data/hadoop/kerberos" {
  capabilities = ["read"]
}
path "secret/data/hadoop/kafka" {
  capabilities = ["read"]
}
path "secret/data/hadoop/jks" {
  capabilities = ["read"]
}
path "secret/data/hadoop/hue" {
  capabilities = ["read"]
}
EOF
        # define role
        vault write auth/approle/role/hadoop token_policies="hadoop-policy"

        # generate role-id/secret-id for this new role
        ROLE_ID=$(vault read -field=role_id auth/approle/role/hadoop/role-id)
        SECRET_ID=$(vault write -field=secret_id -force auth/approle/role/hadoop/secret-id)
        echo $ROLE_ID    > $CERTS_DIR/hadoop.approle
        echo $SECRET_ID >> $CERTS_DIR/hadoop.approle
        chmod 400          $CERTS_DIR/hadoop.approle

        # put passwords
        log "Generating random passwords..."
        vault kv put secret/hadoop/postgres hive="$(openssl rand -base64 24)" hue="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/kerberos password="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/kafka cluster_id="4L99ydgNTwKC-gA5TSbJOQ"
        vault kv put secret/hadoop/jks storepass="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/hue secret_key="$(openssl rand -base64 24)"

        # enable PKI
        vault secrets enable pki
        vault secrets tune -max-lease-ttl=87600h pki       # must-have
        # generate Root CA
        vault write -field=certificate pki/root/generate/internal common_name="secman-ca" ttl=87600h > $CERTS_DIR/root_ca.crt
        # create a role for nodes to sign their public keys
        vault write pki/roles/secman allowed_domains="host" allow_subdomains=true ttl=87599h

        touch $VAULT_HOME/data/initialized
        info "Vault initialized"
    else
        vault operator unseal "$(cat $VAULT_HOME/data/unseal.key)"
        info "OK: Vault unsealed"
    fi
fi

# getting vault token for this session
while [ ! -f $CERTS_DIR/hadoop.approle ]; do sleep 1; log "."; done
until curl --silent --fail http://$MASTER_HOST:8200/v1/sys/health | grep --quiet '"sealed":false'; do
    log "Waiting for Vault to be unsealed..."
    sleep 1
done
ROLE_ID=$(sed -n '1p' "$CERTS_DIR/hadoop.approle")
SECRET_ID=$(sed -n '2p' "$CERTS_DIR/hadoop.approle")
export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
check_env "VAULT_TOKEN"



# generate SSL certificates to enable SASL to auth data transfer protocol
# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
MY_KEYSTORE="$CERTS_DIR/$MY_HOSTNAME.keystore.jks"
TRUSTSTORE="$CERTS_DIR/truststore.jks"
JKS_PASSWORD=$(vault kv get -field=storepass secret/hadoop/jks)
check_env "JKS_PASSWORD"
if [ ! -f "$MY_KEYSTORE" ]; then
    log "Generating SSL for $MY_HOSTNAME..."

    # Generate a private key (Java8 needs -storetype pkcs12!)
    keytool -genkeypair -alias "$MY_HOSTNAME" -keyalg RSA -validity 3650 \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD" -dname "CN=$MY_HOSTNAME" -storetype pkcs12

    # Generate a CSR
    keytool -certreq -alias "$MY_HOSTNAME" -keystore "$MY_KEYSTORE" \
        -storepass "$JKS_PASSWORD" -file "$CERTS_DIR/$MY_HOSTNAME.csr"

    # Send CSR to Vault and get a signed certificate back
    vault write -format=json pki/sign/secman \
        common_name="$MY_HOSTNAME" csr=@"$CERTS_DIR/$MY_HOSTNAME.csr" ttl="3648d" | jq --raw-output .data.certificate > "$CERTS_DIR/$MY_HOSTNAME.crt"

    # Import the Root CA and the signed cert into the Keystore
    sleep $ZK_ID    # must-have to avoid race-conditions!
    keytool -importcert -alias rootca -file $CERTS_DIR/root_ca.crt \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD" -noprompt || true
    keytool -importcert -alias rootca -trustcacerts -file "$CERTS_DIR/root_ca.crt" \
        -keystore "$TRUSTSTORE" -storepass "$JKS_PASSWORD" -noprompt || true
    keytool -importcert -alias "$MY_HOSTNAME" -file "$CERTS_DIR/$MY_HOSTNAME.crt" \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD"

    rm --verbose --force $CERTS_DIR/$MY_HOSTNAME.csr $CERTS_DIR/$MY_HOSTNAME.crt
    info "SSL certificates stored in $MY_KEYSTORE"
else
    info "OK: Keystore already exists: $MY_KEYSTORE"
fi


# start Postgres
if [[ "$IS_MASTER" == "true" ]]; then
    log "Starting PostgreSQL..."
    PG_DATA_DIR="/var/lib/postgresql/16/main"

    sudo chown -R postgres:postgres /var/lib/postgresql/16
    if sudo [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then                                # sudo needed for real Ubuntu
        log "First time run. Initializing PostgreSQL database..."
        sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D "$PG_DATA_DIR"        # initdb must be run as the postgres user
    else
        info "OK: Database exists in $PG_DATA_DIR"
    fi
    sudo service postgresql start

    HIVE_DB_PASSWORD=$(vault kv get -field=hive secret/hadoop/postgres)
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

    HUE_DB_PASSWORD=$(vault kv get -field=hue secret/hadoop/postgres)
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
    default_realm = DEV.DF.SBRF.RU
    ticket_lifetime = 24h
    renew_lifetime = 7d

[realms]
    DEV.DF.SBRF.RU = {
        kdc = $MASTER_HOST
    }
EOF

# for HUE to renew TGT
cat << EOF | sudo tee /etc/krb5kdc/kdc.conf
[realms]
    DEV.DF.SBRF.RU = {
        max_life = 24h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF

# create simple kadm5.acl to avoid startup errors
echo "*/admin@DEV.DF.SBRF.RU *" | sudo tee /etc/krb5kdc/kadm5.acl


# HDFS
cat <<EOF > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$MASTER_HOST:9000</value>
        <description>give the datanodes address of the namenode</description>
    </property>
    <property>
        <name>hadoop.security.authentication</name>
        <value>kerberos</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.hosts</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hue.groups</name>
        <value>*</value>
        <description>FIX: User: hue is not allowed to impersonate hadoop</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.hosts</name>
        <value>*</value>
        <description>FIX: User: hive/...@DEV.DF.SBRF.RU is not allowed to impersonate hadoop/datanode1.host@DEV.DF.SBRF.RU</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.groups</name>
        <value>*</value>
        <description>FIX: User: hive/...@DEV.DF.SBRF.RU is not allowed to impersonate hadoop/datanode1.host@DEV.DF.SBRF.RU</description>
    </property>
</configuration>
EOF

cat <<EOF > $HADOOP_CONF_DIR/mapred-site.xml
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
    <description>Hive/Tez FIX: InvalidInputException: Input path does not exist: file:/tmp/hadoop/guid/hive_...7923819630025608960-1/dummy_path</description>
  </property>
</configuration>
EOF

# note! HTTP/ principal is needed (!) for secured old Hadoops
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
        <value>hadoop/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>dfs.web.authentication.kerberos.principal</name>
        <value>HTTP/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>dfs.web.authentication.kerberos.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>hadoop/$MY_HOSTNAME@DEV.DF.SBRF.RU</value>
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

cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
        <description>Needed for Tez</description>
    </property>
    <property>
        <name>yarn.resourcemanager.principal</name>
        <value>hadoop/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>yarn.nodemanager.principal</name>
        <value>hadoop/$MY_HOSTNAME@DEV.DF.SBRF.RU</value>
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


# setup Apache Spark
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
export HBASE_LIBS="$HBASE_HOME/lib/hbase-client-2.4.12.jar:\
$HBASE_HOME/lib/hbase-common-2.4.12.jar:\
$HBASE_HOME/lib/hbase-protocol-2.4.12.jar:\
$HBASE_HOME/lib/hbase-protocol-shaded-2.4.12.jar:\
$HBASE_HOME/lib/hbase-server-2.4.12.jar:\
$HBASE_HOME/lib/hbase-mapreduce-2.4.12.jar:\
$HBASE_HOME/lib/hbase-shaded-miscellaneous-3.5.1.jar:\
$HBASE_HOME/lib/hbase-shaded-protobuf-3.5.1.jar:\
$HBASE_HOME/lib/hbase-shaded-netty-3.5.1.jar:\
$HBASE_HOME/lib/hbase-unsafe-3.5.1.jar:\
$HBASE_HOME/lib/protobuf-java-2.5.0.jar"

cat <<EOF > $SPARK_HOME/conf/spark-defaults.conf
spark.master                                     yarn
spark.history.fs.logDirectory                    hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.dir                               hdfs://$MASTER_HOST:9000/spark/logs
spark.eventLog.enabled                           true
spark.yarn.jars                                  hdfs:///spark/libs/*.jar
spark.hadoop.hive.metastore.uris                 thrift://$MASTER_HOST:9083
spark.hadoop.hive.metastore.sasl.enabled         true
spark.hadoop.hive.metastore.kerberos.principal   hive/$MASTER_HOST@DEV.DF.SBRF.RU
spark.sql.hive.metastore.jars                    $HIVE_HOME/lib/*
spark.kerberos.principal                         hadoop/$MY_HOSTNAME@DEV.DF.SBRF.RU
spark.kerberos.keytab                            $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.history.kerberos.enabled                   true
spark.history.kerberos.principal                 hadoop/$MY_HOSTNAME@DEV.DF.SBRF.RU
spark.history.kerberos.keytab                    $KEYTABS_DIR/$MY_HOSTNAME.keytab
spark.driver.extraClassPath                      $HBASE_HOME/conf:$HBASE_LIBS
spark.executor.extraClassPath                    $HBASE_HOME/conf:$HBASE_LIBS
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
        <name>hive.metastore.sasl.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.metastore.kerberos.principal</name>
        <value>hive/$MASTER_HOST@DEV.DF.SBRF.RU</value>
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
        <value>hive/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>hive.server2.authentication.kerberos.keytab</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
      <name>hive.server2.webui.use.spnego</name>
      <value>false</value>
      <description>For old Hive</description>
    </property>

    <!-- Check if we need this shit -->
    <property>
      <name>hive.server2.webui.spnego.principal</name>
      <value>HTTP/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
      <name>hive.server2.webui.spnego.keytab</name>
      <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
      <name>hive.users.in.admin.role</name>
      <value>hive</value>
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


# setup HBase
# Fix SASL issue (secured HBase only): https://issues.apache.org/jira/browse/HDFS-16644
find $HBASE_HOME/lib -name "hadoop-*.jar" -delete
find $HBASE_HOME/lib -name "guava-*.jar" -delete
find $HBASE_HOME/lib -name "hbase-shaded-client-*.jar" -delete
cp -v $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar $HBASE_HOME/lib/

{
  #echo "export HBASE_CLASSPATH_PREFIX=\"/opt/hbase/lib/mariposa-hbase-patch-2.5.13.jar\""
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
        <value>hbase/$MASTER_HOST@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>hbase.master.keytab.file</name>
        <value>$KEYTABS_DIR/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>hbase.regionserver.kerberos.principal</name>
        <value>hbase/$MY_HOSTNAME@DEV.DF.SBRF.RU</value>
    </property>
    <property>
        <name>hbase.regionserver.keytab.file</name>
        <value>$KEYTABS_DIR/$MY_HOSTNAME.keytab</value>
    </property>
</configuration>
EOF


# ZOOKEEPER
# setup ZK for each node (ZK_ID must be a unique number for every node, e.g. 1,2,3)
echo "$ZK_ID" > $ZOOKEEPER_HOME/data/myid
{
  echo 'export SERVER_JVMFLAGS="$SERVER_JVMFLAGS -Djava.security.auth.login.config=$ZOOKEEPER_HOME/conf/jaas.conf"'
  echo 'export CLIENT_JVMFLAGS="$CLIENT_JVMFLAGS -Djava.security.auth.login.config=$ZOOKEEPER_HOME/conf/jaas.conf"'
} >> $ZOOKEEPER_HOME/bin/zkEnv.sh

cat <<EOF > $ZOOKEEPER_HOME/conf/zoo.cfg
tickTime=1000
initLimit=10
syncLimit=5
dataDir=$ZOOKEEPER_HOME/data
clientPort=2181

authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
requireClientAuthScheme=sasl

server.1=$MASTER_HOST:2888:3888
EOF

count=2     # "1" is already set for $MASTER_HOST
IFS=','
for worker in $WORKER_HOSTS; do
    echo "server.$count=$worker:2888:3888" >> $ZOOKEEPER_HOME/conf/zoo.cfg
    count=$((count + 1))
done
unset IFS

cat <<EOF > $ZOOKEEPER_HOME/conf/jaas.conf
Server {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    useTicketCache=false
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="zookeeper/$MY_HOSTNAME@DEV.DF.SBRF.RU"
    storeKey=true;
};

Client {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    useTicketCache=false
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="zookeeper/$MY_HOSTNAME@DEV.DF.SBRF.RU"
    storeKey=true;
};
EOF


# setup Apache Kafka
# format: id1@host1:9093,id2@host2:9093,id3@host3:9093 (hardcoding the master as ID 1 and workers starting from 2)
VOTERS="1@$MASTER_HOST:9093"
count=2
IFS=','
for worker in $WORKER_HOSTS; do
    VOTERS="$VOTERS,$count@$worker:9093"
    count=$((count + 1))
done
unset IFS

cat <<EOF > $KAFKA_HOME/config/server.properties
# Role: every node acts as both a Broker and a Controller
process.roles=broker,controller
node.id=$ZK_ID
controller.quorum.voters=$VOTERS

# Network settings
listeners=SASL_SSL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
inter.broker.listener.name=SASL_SSL
advertised.listeners=SASL_SSL://$MY_HOSTNAME:9092
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:SASL_SSL,SASL_SSL:SASL_SSL

# Kerberos settings
sasl.enabled.mechanisms=GSSAPI
sasl.mechanism.inter.broker.protocol=GSSAPI
sasl.mechanism.controller.protocol=GSSAPI
sasl.kerberos.service.name=kafka

# SSL Settings
ssl.keystore.location=$MY_KEYSTORE
ssl.keystore.password=$JKS_PASSWORD
ssl.key.password=$JKS_PASSWORD
ssl.truststore.location=$TRUSTSTORE
ssl.truststore.password=$JKS_PASSWORD
ssl.endpoint.identification.algorithm=HTTPS

# Log & Data
log.dirs=$KAFKA_HOME/data
num.partitions=3
offsets.topic.replication.factor=3
EOF

cat <<EOF > $KAFKA_HOME/config/kafka_jaas.conf
KafkaServer {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="kafka/$MY_HOSTNAME@DEV.DF.SBRF.RU";
};

KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab="$KEYTABS_DIR/$MY_HOSTNAME.keytab"
    principal="kafka/$MY_HOSTNAME@DEV.DF.SBRF.RU";
};
EOF

cat <<EOF > $KAFKA_HOME/config/sasl.properties
security.protocol=SASL_SSL
sasl.kerberos.service.name=kafka
ssl.truststore.location=$TRUSTSTORE
ssl.truststore.password=$JKS_PASSWORD
EOF



# setup Tez
cat <<EOF > $TEZ_HOME/conf/tez-site.xml
<configuration>
    <property>
        <name>tez.lib.uris</name>
        <value>\${fs.defaultFS}/apps/tez/tez.tar.gz</value>
        <description>Libs location on HDFS</description>
    </property>
</configuration>
EOF
echo "export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:$TEZ_HOME/conf:$TEZ_HOME/*.jar:$TEZ_HOME/lib/protobuf*.jar" >> /opt/hadoop/etc/hadoop/hadoop-env.sh



# =========================
# === starting services ===
# =========================

if [[ "$IS_MASTER" == "true" ]]; then
    # initialize Kerberos KDC Database
    if sudo [ ! -f "/var/lib/krb5kdc/principal" ]; then         # sudo needed for real Ubuntu
        log "First time run. Initializing Kerberos KDC..."
        KRB5_PASSWORD=$(vault kv get -field=password secret/hadoop/kerberos)
        check_env "KRB5_PASSWORD"
        sudo kdb5_util create -s -P "$KRB5_PASSWORD"

        # create Principals and their proper keytabs
        # -randkey means we don't want a human password; we'll use keytabs
        sudo kadmin.local -q "addprinc -randkey hadoop/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey HTTP/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey zookeeper/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey hbase/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey kafka/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey hive/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "addprinc -randkey hue/$MASTER_HOST@DEV.DF.SBRF.RU"
        sudo kadmin.local -q "xst -k $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@DEV.DF.SBRF.RU HTTP/$MASTER_HOST@DEV.DF.SBRF.RU zookeeper/$MASTER_HOST@DEV.DF.SBRF.RU hbase/$MASTER_HOST@DEV.DF.SBRF.RU kafka/$MASTER_HOST@DEV.DF.SBRF.RU hive/$MASTER_HOST@DEV.DF.SBRF.RU hue/$MASTER_HOST@DEV.DF.SBRF.RU"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey hadoop/$worker@DEV.DF.SBRF.RU"
            sudo kadmin.local -q "addprinc -randkey HTTP/$worker@DEV.DF.SBRF.RU"
            sudo kadmin.local -q "addprinc -randkey zookeeper/$worker@DEV.DF.SBRF.RU"
            sudo kadmin.local -q "addprinc -randkey hbase/$worker@DEV.DF.SBRF.RU"
            sudo kadmin.local -q "addprinc -randkey kafka/$worker@DEV.DF.SBRF.RU"
            sudo kadmin.local -q "xst -k $KEYTABS_DIR/$worker.keytab hadoop/$worker@DEV.DF.SBRF.RU HTTP/$worker@DEV.DF.SBRF.RU zookeeper/$worker@DEV.DF.SBRF.RU hbase/$worker@DEV.DF.SBRF.RU kafka/$worker@DEV.DF.SBRF.RU"
        done
        unset IFS

        # set keytabs to be read-only by hadoop
        sudo chown hadoop:hadoop $KEYTABS_DIR/*.keytab
        sudo chmod 400 $KEYTABS_DIR/*.keytab
        
        log "Kerberos Principals and keytabs created"
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

    # start Zookeeper
    log "Starting Zookeeper..."
    rm --verbose --force $ZOOKEEPER_HOME/data/zookeeper_server.pid
    zkServer.sh start

    # create directories on HDFS
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@DEV.DF.SBRF.RU && klist
    hdfs dfs -mkdir -p /spark/logs           # must-have
    hdfs dfs -mkdir -p /user/hadoop          # opt, for HUE
    hdfs dfs -mkdir -p /user/hive/warehouse  # must-have
    hdfs dfs -mkdir -p /tmp/hive             # must-have
    hdfs dfs -chmod 777 /tmp/hive            # must-have
    if ! hdfs dfs -test -e /apps/tez/tez.tar.gz; then
        hdfs dfs -mkdir -p /apps/tez
        hdfs dfs -put $TEZ_HOME/share/tez.tar.gz /apps/tez/
    fi

    # start Spark
    log "Starting Spark History Server..."
    start-history-server.sh

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
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue migrate)        # ("cd" needed)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue kt_renewer > $HUE_HOME/logs/kt_renewer.log 2>&1 &)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue runserver 0.0.0.0:8888 > $HUE_HOME/logs/hue.log 2>&1 &)
    else
        warn "SKIP_HUE is true => HUE is not started"
    fi

    # opt: copy Spark libs to HDFS for better performance
    if ! hdfs dfs -test -e /spark/libs; then
        log "First time run. Uploading Spark JARs to HDFS... (it may take some time)..."
        hdfs dfs -mkdir -p /spark/libs
        hdfs dfs -put $SPARK_HOME/jars/*.jar /spark/libs/
    else
        info "OK: Spark JARs already loaded into HDFS"
    fi

    # start HBase with a new kinit
    log "Starting HBase Master..."
    hdfs dfs -mkdir /hbase && hdfs dfs -chown hbase:hadoop /hbase    # must-have
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hbase/$MASTER_HOST@DEV.DF.SBRF.RU && klist
    hbase-daemon.sh start master
    hbase-daemon.sh start thrift        # for HUE
else      # WORKERs
    # wait for KDC
    until nc -zv $MASTER_HOST 88; do sleep 1; done

    # start Hadoop
    log "Starting HDFS..."
    hdfs --daemon start datanode
    yarn --daemon start nodemanager

    # start Zookeeper
    log "Starting Zookeeper..."
    rm --verbose --force $ZOOKEEPER_HOME/data/zookeeper_server.pid
    zkServer.sh start

    # start HBase
    sleep 15     # simple sync with master
    log "Starting HBase RegionServer..."
    kinit -kt $KEYTABS_DIR/$MY_HOSTNAME.keytab hbase/$MY_HOSTNAME@DEV.DF.SBRF.RU && klist
    hbase-daemon.sh start regionserver
fi

# start Kafka on all nodes
log "Starting Kafka Server..."
if [ ! -f "$KAFKA_HOME/data/meta.properties" ]; then
    log "First time run. Formatting Kafka storage"
    KAFKA_CLUSTER_ID=$(vault kv get -field=cluster_id secret/hadoop/kafka)
    check_env "KAFKA_CLUSTER_ID"
    $KAFKA_HOME/bin/kafka-storage.sh format --cluster-id $KAFKA_CLUSTER_ID --config $KAFKA_HOME/config/server.properties
else
    info "OK: Kafka storage already formatted"
fi
kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties


# infinite loop
kinit -kt $KEYTABS_DIR/$(hostname).keytab hadoop/$(hostname)@DEV.DF.SBRF.RU && klist
log "Done!"
if [[ -f /.dockerenv ]]; then
  tail -f /dev/null
fi
