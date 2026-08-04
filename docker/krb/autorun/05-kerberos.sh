#!/usr/bin/env bash
# Kerberos
set -euo pipefail
source utils.sh
source .env

check_env "MASTER_HOST"
check_env "IS_MASTER"


# main config file
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


if [[ "$IS_MASTER" == "true" ]]; then
    check_env "WORKER_HOSTS"
    check_env "KEYTABS_DIR"

    # initialize Kerberos KDC Database
    if sudo [ ! -f "/var/lib/krb5kdc/principal" ]; then         # sudo needed for real Ubuntu
        log "First time run. Initializing Kerberos KDC..."
        KRB5_PASSWORD=$(vault kv get -field=password secret/hadoop/kerberos)
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
        
        log "Kerberos Principals and keytabs created"
    fi

    # start Kerberos services
    log "Starting Kerberos..."
    sudo service krb5-kdc start
    sudo service krb5-admin-server start
    until nc -zv $MASTER_HOST 88; do sleep 1; done
fi
