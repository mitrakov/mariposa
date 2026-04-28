#!/usr/bin/env bash
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
function check_os() {
    local result=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        result="MacOS $(sw_vers -productVersion) (Build: $(sw_vers -buildVersion))"
    elif [[ -f /etc/os-release ]]; then
        # linux distributions with /etc/os-release
        source /etc/os-release
        result="$ID $VERSION_ID ($PRETTY_NAME)"
    elif [[ -f /etc/redhat-release ]]; then
        # fallback for older RHEL systems without /etc/os-release
        result=$(cat /etc/redhat-release)
    else
        error "Unable to detect operating system"
        exit 1
    fi

    info "OS: $result"
}
function check_primary_ip() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use route and ifconfig
        primary_interface=$(route get default | grep interface | awk '{print $2}')
        ipv4_addr=$(ifconfig "$primary_interface" | grep 'inet ' | awk '{print $2}')
    else
        # Linux - use ip command
        primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)
        ipv4_addr=$(ip -4 addr show "$primary_interface" | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    info "Default IPv4 address: $ipv4_addr"
}
function check_hostname() {
    info "Hostname: $(hostname)"
}
function check_java() {
    if command -v java &> /dev/null; then
        java_version=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    
        if [[ -n "$java_version" ]]; then
            info "Java version: $java_version"
        else
            warn "Cannot detect Java version"
        fi
    else
        warn "'java' command not found"
    fi
}



# =====
# todo: remove this shit
export HADOOP_NICENESS=0
export HADOOP_SKIP_NICE=1
export HDFS_DATANODE_SECURE_EXTRA_OPTS="-Dhadoop.security.dns.interface=default"
# todo: rm renice from xmls


# checks
check_env "JAVA_HOME"
check_env "HADOOP_HOME"
check_env "HADOOP_CONF_DIR"
check_env "IS_MASTER"
check_env "MASTER_HOST"
check_env "WORKER_HOSTS"
check_os
check_hostname
check_primary_ip
check_java

# todo: do we need it?
log "Update renice..."
echo -e '#!/bin/sh\nexit 0' | sudo tee /usr/local/bin/renice
sudo chmod +x /usr/local/bin/renice

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

[domain_realm]
    .mariposa.com = MARIPOSA.COM
    mariposa.com = MARIPOSA.COM
EOF

cat << EOF | sudo tee /etc/krb5kdc/kdc.conf
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    MARIPOSA.COM = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = /etc/krb5kdc/kadm5.keytab
        acl_file = /etc/krb5kdc/kadm5.acl
        key_stash_file = /etc/krb5kdc/stash
        kdc_ports = 88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF

echo "*/admin@MARIPOSA.COM *" | sudo tee /etc/krb5kdc/kadm5.acl

# minimal setup for HDFS
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
        <name>hadoop.security.authorization</name>
        <value>true</value>
    </property>
    <property>
      <name>hadoop.proxyuser.hue.hosts</name>
      <value>*</value>
      <description>add permissions for HUE</description>
    </property>
    <property>
      <name>hadoop.proxyuser.hue.groups</name>
      <value>*</value>
      <description>add permissions for HUE</description>
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
        <description>replication factor (default 3)</description>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>$HADOOP_HOME/dfs/name</value>
        <description>switch default "/tmp/hadoop-hadoop/dfs/name" to stable path</description>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>$HADOOP_HOME/dfs/data</value>
        <description>switch default "/tmp/hadoop-hadoop/dfs/data" to stable path</description>
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
        <value>0.0.0.0:1004</value>
    </property>
    <property>
        <name>dfs.datanode.http.address</name>
        <value>0.0.0.0:1006</value>
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
        <name>dfs.webhdfs.enabled</name>
        <value>true</value>
        <description>Enable WebHDFS for HUE</description>
    </property>
</configuration>
EOF

# minimal setup for Yarn
cat <<EOF > $HADOOP_CONF_DIR/yarn-site.xml
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$MASTER_HOST</value>
        <description>Tell Yarn the namenode address</description>
    </property>
    <property>
        <name>yarn.resourcemanager.process-priority</name>
        <value>0</value>
        <description>Do not try to change priority of Res-Manager</description>
    </property>
    <property>
        <name>yarn.nodemanager.process-priority</name>
        <value>0</value>
        <description>Do not try to change priority of Node managers</description>
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
        check_env "KRB5_PASSWORD"
        sudo kdb5_util create -s -P "$KRB5_PASSWORD"
        
        # create Principals and their proper keytabs
        # -randkey means we don't want a human password; we'll use keytabs
        sudo kadmin.local -q "addprinc -randkey nn/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "addprinc -randkey HTTP/$MASTER_HOST@MARIPOSA.COM"
        sudo kadmin.local -q "xst -k /etc/security/keytabs/nn.keytab nn/$MASTER_HOST@MARIPOSA.COM HTTP/$MASTER_HOST@MARIPOSA.COM"
        IFS=','
        for worker in $WORKER_HOSTS; do
            sudo kadmin.local -q "addprinc -randkey dn/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "addprinc -randkey HTTP/$worker@MARIPOSA.COM"
            sudo kadmin.local -q "xst -k /etc/security/keytabs/$worker.keytab dn/$worker@MARIPOSA.COM HTTP/$worker@MARIPOSA.COM"
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
    HADOOP_NICENESS=0 nice -n 0 hdfs --daemon start namenode
    HADOOP_NICENESS=0 nice -n 0 yarn --daemon start resourcemanager
else      # WORKERs
    # wait for the master to create our specific keytab
    MY_HOSTNAME=$(hostname)
    while [ ! -f "/etc/security/keytabs/$MY_HOSTNAME.keytab" ]; do
      log "Waiting for /etc/security/keytabs/$MY_HOSTNAME.keytab..."
      sleep 2
    done

    # rename worker-specific keytab to the generic name HDFS expects in hdfs-site.xml
    mv -fv "/etc/security/keytabs/$MY_HOSTNAME.keytab" /etc/security/keytabs/dn.keytab

    log "Starting HDFS..."
    # we use sudo because the process MUST start as root to grab port 1004
    sudo env "PATH=$PATH" HADOOP_NICENESS=0 nice -n 0 hdfs --daemon start datanode
    HADOOP_NICENESS=0 nice -n 0 yarn --daemon start nodemanager
fi

# infinite loop
log "Done!"
tail -f /dev/null
