#!/usr/bin/env bash
set -euo pipefail
source utils.sh
source .env

check_env "JKS_PASSWORD"

# add your app code here
echo "Hello world"

# optional: rm .env file that may contain sensetive data
rm --verbose .env
