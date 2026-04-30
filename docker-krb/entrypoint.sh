#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-krb:1.0.0
# kinit -kt /etc/security/keytabs/$(hostname).keytab namenode/$(hostname)@MARIPOSA.COM
set -euo pipefail  # exit on any error, undefined variable, or pipe failure

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # no colour
function log() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [LOG]   $1"
    echo -e "${GREEN}${message}${NC}"
}
function info() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $1"
    echo -e "${BLUE}${message}${NC}"
}
function warn() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $1"
    echo -e "${YELLOW}${message}${NC}"
}
function error() {
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${message}${NC}"
}



# checks

log "Generate SSL certificates..."
# DO NOT use _HOST in XML Configs! Use $MY_HOSTNAME (or $MASTER_HOST) instead!
MY_HOSTNAME=$(hostname)

# generate temp self-signed SSL certificate to enable SASL to auth data transfer protocol
# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
if [ ! -f "$HADOOP_CONF_DIR/certs/keystore.jks" ]; then
  keytool -genkeypair \
    -alias hadoop \
    -keyalg RSA \
    -keysize 2048 \
    -validity 9999 \
    -keystore $HADOOP_CONF_DIR/certs/keystore.jks \
    -storepass $JKS_PASSWORD \
    -keypass $JKS_PASSWORD \
    -dname "CN=$MY_HOSTNAME" \
    -storetype PKCS12 \
    -noprompt
else
    info "OK. The keystore.jks found for $MY_HOSTNAME."
fi

log "Creating configs..."

# setup Kerberos
cat << EOF | sudo tee /etc/krb5.conf
[libdefaults]
    default_realm = MARIPOSA.COM

[realms]
    MARIPOSA.COM = {
        kdc = $MASTER_HOST
    }
EOF

# create simple kadm5.acl to avoid startup errors
echo "*/admin@MARIPOSA.COM *" | sudo tee /etc/krb5kdc/kadm5.acl

# minimal setup for HDFS
# Quote 'EOF' to prevent shell expansion inside the heredoc
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
        <value>namenode/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>/etc/security/keytabs/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>datanode/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.datanode.keytab.file</name>
        <value>/etc/security/keytabs/$MY_HOSTNAME.keytab</value>
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
        <value>namenode/$MASTER_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>/etc/security/keytabs/$MASTER_HOST.keytab</value>
    </property>
    <property>
        <name>yarn.nodemanager.principal</name>
        <value>datanode/$MY_HOSTNAME@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.nodemanager.keytab</name>
        <value>/etc/security/keytabs/$MY_HOSTNAME.keytab</value>
    </property>
</configuration>
EOF

# this is necessary for SASL data-transfer protocol to enable https
cat <<EOF > $HADOOP_CONF_DIR/ssl-server.xml
<configuration>
  <property>
    <name>ssl.server.keystore.location</name>
    <value>$HADOOP_CONF_DIR/certs/keystore.jks</value>
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



# =========================
# === starting services ===
# =========================

if [[ "$IS_MASTER" == "true" ]]; then
    # initialize Kerberos KDC Database
    if [ ! -f "/var/lib/krb5kdc/principal" ]; then
        log "First time run. Initializing Kerberos KDC..."
        sudo kdb5_util create -s -P "$KRB5_PASSWORD"
        
        # create Principals and their proper keytabs
        # -randkey means we don't want a human password; we'll use keytabs
        sudo kadmin.local -q "addprinc -randkey namenode/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k /etc/security/keytabs/$MASTER_HOST.keytab namenode/$MASTER_HOST@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey datanode/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k /etc/security/keytabs/$worker.keytab datanode/$worker@MARIPOSA.COM"
        done
        unset IFS

        # set keytabs to be read-only by hadoop
        sudo chown hadoop:hadoop /etc/security/keytabs/*.keytab
        sudo chmod 400 /etc/security/keytabs/*.keytab
        
        log "Kerberos Principals and keytabs created."
    fi

    # start Kerberos services
    log "Starting Kerberos..."
    sudo service krb5-kdc start
    sudo service krb5-admin-server start

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
else      # WORKERs
    # make sure keytab files are available
    while [ ! -f "/etc/security/keytabs/$MY_HOSTNAME.keytab" ]; do
      log "Waiting for $MY_HOSTNAME.keytab"
      sleep 2
    done

    log "Starting HDFS..."
    # use this commands instead of "hdfs start namenode" to avoid run-on-privilidged-port exception
    hadoop --config $HADOOP_CONF_DIR org.apache.hadoop.hdfs.server.datanode.DataNode > $HADOOP_HOME/logs/datanode.log 2>&1 &
    yarn --daemon start nodemanager
fi

# infinite loop
log "Done!"
tail -f /dev/null
