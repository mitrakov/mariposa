#!/usr/bin/env bash
# get VAULT_TOKEN for HashiCorp
set -euo pipefail
. utils.sh
. .env

check_env "CERTS_DIR"
check_env "MASTER_HOST"
check_file "$CERTS_DIR/hadoop.approle"

ROLE_ID=$(sed   --quiet '1p' "$CERTS_DIR/hadoop.approle")
SECRET_ID=$(sed --quiet '2p' "$CERTS_DIR/hadoop.approle")
export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
check_env "VAULT_TOKEN"
echo "export VAULT_TOKEN=$VAULT_TOKEN" >> .env
