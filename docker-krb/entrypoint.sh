#!/usr/bin/env bash
# entrypoint.sh for image: mitrakov/hadoop-krb:1.0.0
# kinit -kt /etc/security/keytabs/nn.keytab nn/namenode.host@MARIPOSA.COM
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

log "Creating configs..."

# setup Kerberos
cat << EOF | sudo tee /etc/krb5.conf
[libdefaults]
    default_realm = MARIPOSA.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    MARIPOSA.COM = {
        kdc = namenode.host
        admin_server = namenode.host
    }
EOF

cat << EOF | sudo tee /etc/krb5kdc/kdc.conf
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    MARIPOSA.COM = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = /var/lib/krb5kdc/kadm5.keytab
        acl_file = /var/lib/krb5kdc/kadm5.acl
        key_stash_file = /var/lib/krb5kdc/stash
        kdc_ports = 88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF

echo "*/admin@MARIPOSA.COM *" | sudo tee /var/lib/krb5kdc/kadm5.acl

# minimal setup for HDFS
# Quote 'EOF' to prevent shell expansion inside the heredoc
cat <<'EOF' > $HADOOP_CONF_DIR/core-site.xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://namenode.host:9000</value>
    </property>
    <property>
        <name>hadoop.security.authentication</name>
        <value>kerberos</value>
    </property>
    <property>
        <name>hadoop.security.authorization</name>
        <value>false</value>
    </property>
</configuration>
EOF



# minimal HDFS setup
# Hadoop replaces _HOST with the actual hostname automatically
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
        <value>nn/_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.namenode.keytab.file</name>
        <value>/etc/security/keytabs/nn.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.kerberos.principal</name>
        <value>dn/_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>dfs.datanode.keytab.file</name>
        <value>/etc/security/keytabs/dn.keytab</value>
    </property>
    <property>
        <name>dfs.datanode.address</name>
        <value>0.0.0.0:10019</value>
    </property>
    <property>
        <name>dfs.data.transfer.protection</name>
        <value>authentication</value>
    </property>
    <property>
        <name>dfs.block.access.token.enable</name>
        <value>true</value>
        <description>Enable Block Access Tokens (for Kerberos)</description>
    </property>
    <property>
      <name>ignore.secure.ports.for.testing</name>
      <value>true</value>
      <description>Required for some Hadoop versions to allow SASL on high ports</description>
    </property>
    <property>
        <name>dfs.namenode.datanode.registration.ip-hostname-check</name>
        <value>false</value>
        <description>Turn off strict hostname checking in Docker networks</description>
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
        <value>nn/namenode.host@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.keytab</name>
        <value>/etc/security/keytabs/nn.keytab</value>
    </property>
    <property>
        <name>yarn.nodemanager.principal</name>
        <value>dn/_HOST@MARIPOSA.COM</value>
    </property>
    <property>
        <name>yarn.nodemanager.keytab</name>
        <value>/etc/security/keytabs/dn.keytab</value>
    </property>
    <property>
        <name>yarn.resourcemanager.principal.hostname-check</name>
        <value>false</value>
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
        sudo kadmin.local -q "addprinc -randkey nn/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k /etc/security/keytabs/nn.keytab nn/$MASTER_HOST@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey dn/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k /etc/security/keytabs/$worker.keytab dn/$worker@MARIPOSA.COM"
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
    MY_HOSTNAME=$(hostname)
    MY_KEYTAB="/etc/security/keytabs/$MY_HOSTNAME.keytab"
    while [ ! -f "$MY_KEYTAB" ]; do
      log "Waiting for $MY_KEYTAB..."
      sleep 2
    done

    # update hdfs-site.xml/yarn-site.xml with proper keytabs
    sed -i "s|/etc/security/keytabs/dn.keytab|$MY_KEYTAB|g" $HADOOP_CONF_DIR/hdfs-site.xml
    sed -i "s|/etc/security/keytabs/dn.keytab|$MY_KEYTAB|g" $HADOOP_CONF_DIR/yarn-site.xml

    log "Starting HDFS..."
    # use this commands instead of "hdfs start namenode" to avoid run-on-privilidged-port exception
    hadoop --config $HADOOP_CONF_DIR org.apache.hadoop.hdfs.server.datanode.DataNode > $HADOOP_HOME/logs/datanode.log 2>&1 &
    yarn --daemon start nodemanager
fi

# infinite loop
log "Done!"
tail -f /dev/null
