#!/usr/bin/env bash
# Apache Hadoop
set -euo pipefail
. utils.sh
. .env

check_env "MY_KEYSTORE"
check_env "KEYTABS_DIR"
check_env "MY_HOSTNAME"
check_env "HADOOP_CONF_DIR"
check_env "MASTER_HOST"
check_env "HADOOP_HOME"
check_env "IS_MASTER"
check_env "JKS_PASSWORD"
check_file "$MY_KEYSTORE"
check_file "$KEYTABS_DIR/$MY_HOSTNAME.keytab"

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
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
    </property>
    <property>
        <name>hadoop.proxyuser.hive.groups</name>
        <value>*</value>
        <description>FIX: User: hive/namenode.host@MARIPOSA.COM is not allowed to impersonate hadoop/datanode1.host@MARIPOSA.COM</description>
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

# opt: create 2 queues and split resources 50/50 (since: 1.0.3)
cat <<EOF > $HADOOP_CONF_DIR/capacity-scheduler.xml
<configuration>
  <property>
    <name>yarn.scheduler.capacity.root.queues</name>
    <value>default,mariposa</value>
    <description>comma-separated list of queues under the root</description>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.default.capacity</name>
    <value>50</value>
    <description>capacity percentages (must equal 100% total)</description>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.mariposa.capacity</name>
    <value>50</value>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.default.maximum-capacity</name>
    <value>100</value>
    <description>maximum capacity limits for default queue</description>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.mariposa.maximum-capacity</name>
    <value>100</value>
    <description>maximum capacity limits for mariposa queue</description>
  </property>
  <property>
    <name>yarn.scheduler.capacity.root.mariposa.acl_submit_applications</name>
    <value>*</value>
    <description>open ACLs so all users can submit to mariposa queue</description>
  </property>
</configuration>
EOF

log "Starting HDFS..."
if [[ "$IS_MASTER" == "true" ]]; then
    # format HDFS
    if [ ! -f "$HADOOP_HOME/dfs/name/current/VERSION" ]; then
        log "First time run. Formatting Namenode"
        hdfs namenode -format -nonInteractive
    else
        info "OK: Namenode data detected"
    fi

    # start daemons    
    hdfs --daemon start namenode
    yarn --daemon start resourcemanager

    # wait for HDFS to exit Safe Mode
    until nc -zv $MASTER_HOST 9000; do sleep 1; done
    kinit -kt $KEYTABS_DIR/$MASTER_HOST.keytab hadoop/$MASTER_HOST@MARIPOSA.COM && klist
    log "Waiting for HDFS to exit Safe Mode..."
    hdfs dfsadmin -safemode wait
else
    hdfs --daemon start datanode
    yarn --daemon start nodemanager
fi
