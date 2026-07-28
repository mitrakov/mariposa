#!/usr/bin/env bash
# HashiCorp
set -euo pipefail
. utils.sh

check_env "MASTER_HOST"
check_env "IS_MASTER"
echo "export VAULT_ADDR=http://$MASTER_HOST:8200" >> .env
. .env

if [[ "$IS_MASTER" == "true" ]]; then
    check_env "VAULT_HOME"

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
path "pki/sign/mariposa" {
  capabilities = ["update"]
}
path "secret/data/hadoop/postgres" {
  capabilities = ["read"]
}
path "secret/data/hadoop/kerberos" {
  capabilities = ["read"]
}
path "secret/data/hadoop/airflow" {
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
        check_env "CERTS_DIR"
        echo $ROLE_ID    > $CERTS_DIR/hadoop.approle
        echo $SECRET_ID >> $CERTS_DIR/hadoop.approle
        chmod 400          $CERTS_DIR/hadoop.approle

        # put passwords
        log "Generating random passwords..."
        vault kv put secret/hadoop/postgres hive="$(openssl rand -base64 24)" hue="$(openssl rand -base64 24)" airflow="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/kerberos password="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/airflow admin="$(openssl rand -base64 9)"
        vault kv put secret/hadoop/kafka cluster_id="$(openssl rand -base64 6)"
        vault kv put secret/hadoop/jks storepass="$(openssl rand -base64 24)"
        vault kv put secret/hadoop/hue secret_key="$(openssl rand -base64 24)"

        # enable PKI
        vault secrets enable pki
        vault secrets tune -max-lease-ttl=87600h pki       # must-have
        # generate Root CA
        vault write -field=certificate pki/root/generate/internal common_name="mariposa-ca" ttl=87600h > $CERTS_DIR/root_ca.crt
        check_file "$CERTS_DIR/root_ca.crt"
        # create a role for nodes to sign their public keys
        vault write pki/roles/mariposa allowed_domains="host" allow_subdomains=true ttl=87599h

        touch $VAULT_HOME/data/initialized
        info "Vault initialized"
    else
        vault operator unseal "$(cat $VAULT_HOME/data/unseal.key)"
        info "OK: Vault unsealed"
    fi
fi
