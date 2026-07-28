#!/usr/bin/env bash
# generate SSL certificates to enable SASL to auth data transfer protocol 
set -euo pipefail
. utils.sh
. .env

check_env "MASTER_HOST"
check_env "CERTS_DIR"
check_env "ZK_ID"
check_env "JAVA_HOME"

# https://cwiki.apache.org/confluence/display/HADOOP/Secure+DataNode
MY_KEYSTORE="$CERTS_DIR/$(hostname).keystore.jks"
TRUSTSTORE="$CERTS_DIR/truststore.jks"
JKS_PASSWORD=$(vault kv get -field=storepass secret/hadoop/jks)
check_env "JKS_PASSWORD"
echo "MY_KEYSTORE=$MY_KEYSTORE"   >> .env
echo "TRUSTSTORE=$TRUSTSTORE"     >> .env
echo "JKS_PASSWORD=$JKS_PASSWORD" >> .env

if [ ! -f "$MY_KEYSTORE" ]; then
    log "Generating SSL for $(hostname)..."
    check_file "$CERTS_DIR/root_ca.crt"

    # Generate a private key locally (no certificate yet)
    keytool -genkeypair -alias "$(hostname)" -keyalg RSA -validity 3650 \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD" -dname "CN=$(hostname)"

    # Generate a CSR
    keytool -certreq -alias "$(hostname)" -keystore "$MY_KEYSTORE" \
        -storepass "$JKS_PASSWORD" -file "$CERTS_DIR/$(hostname).csr"
    check_file "$CERTS_DIR/$(hostname).csr"

    # Send CSR to Vault and get a signed certificate back
    vault write -format=json pki/sign/mariposa \
        common_name="$(hostname)" csr=@"$CERTS_DIR/$(hostname).csr" ttl="3648d" | jq --raw-output .data.certificate > "$CERTS_DIR/$(hostname).crt"
    check_file "$CERTS_DIR/$(hostname).crt"

    # Import the Root CA and the signed cert into the Keystore ("|| true" needed only for docker as all nodes share the same volume)
    sleep $ZK_ID    # must-have to avoid race-conditions!
    keytool -importcert -alias rootca -file $CERTS_DIR/root_ca.crt \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD" -noprompt || true
    keytool -importcert -alias rootca -trustcacerts -file "$CERTS_DIR/root_ca.crt" \
        -keystore "$TRUSTSTORE" -storepass "$JKS_PASSWORD" -noprompt || true
    keytool -importcert -alias "$(hostname)" -file "$CERTS_DIR/$(hostname).crt" \
        -keystore "$MY_KEYSTORE" -storepass "$JKS_PASSWORD"

    # optional: import rootca to JAVA_HOME (needed for "hdfs fsck /")
    keytool -importcert -alias rootca -file $CERTS_DIR/root_ca.crt \
         -keystore $JAVA_HOME/lib/security/cacerts -storepass "$JKS_PASSWORD" -noprompt || true

    rm --verbose --force $CERTS_DIR/$(hostname).csr $CERTS_DIR/$(hostname).crt
    info "SSL certificates stored in $MY_KEYSTORE"
else
    info "OK: Keystore already exists: $MY_KEYSTORE"
fi
