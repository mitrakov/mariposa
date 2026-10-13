#!/usr/bin/env bash

set -euo pipefail
source utils.sh
source .env

check_env "JKS_PASSWORD"
export "JKS_PASSWORD"

# add your apps here (in bg)

# optional: rm .env file that may contain sensetive data
rm --verbose .env
