#!/usr/bin/env bash
# HUE
set -euo pipefail
. utils.sh
. .env

check_env "IS_MASTER"


# set ccache_path to $HUE_HOME, because on real Ubuntu /var/run/hue/ is getting cleared after reboot
if [[ "$IS_MASTER" == "true" ]]; then
    if [[ ${SKIP_HUE:-} != "true" ]]; then
        check_env "KEYTABS_DIR"
        check_env "MASTER_HOST"
        check_env "HUE_HOME"
        check_env "HIVE_HOME"
        check_env "HUE_DB_PASSWORD"
        check_file "$KEYTABS_DIR/$MASTER_HOST.keytab"

        HUE_PASSWORD=$(vault kv get -field=secret_key secret/hadoop/hue)
        check_env "HUE_PASSWORD"
        cat <<EOF > $HUE_HOME/desktop/conf/hue.ini
[desktop]
  http_host=0.0.0.0
  http_port=8888
  secret_key=$HUE_PASSWORD

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
    ccache_path=$HUE_HOME/hue_krb5_ccache

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
      resourcemanager_port=8088
      resourcemanager_api_url=http://$MASTER_HOST:8088

[beeswax]
  hive_server_host=$MASTER_HOST
  hive_server_port=10000
  hive_conf_dir=$HIVE_HOME/conf
EOF

        log "Starting HUE..."
        hdfs dfs -mkdir -p /user/hadoop          # optional, for HDFS splash screen
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue migrate)        # ("cd" needed)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue kt_renewer > $HUE_HOME/logs/kt_renewer.log 2>&1 &)
        (cd $HUE_HOME && $HUE_HOME/build/env/bin/python $HUE_HOME/build/env/bin/hue runserver 0.0.0.0:8888 > $HUE_HOME/logs/hue.log 2>&1 &)
        
        info "HUE started in foreground. Check logs at $HUE_HOME/logs/"
    else
        warn "SKIP_HUE is true => HUE is not started"
    fi
fi
