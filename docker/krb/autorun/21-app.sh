#!/usr/bin/env bash
set -euo pipefail
source utils.sh
source .env

check_env "JKS_PASSWORD"
export "JKS_PASSWORD"

java -jar /home/hadoop/mariposa-sou-assembly-*.jar &

# optional: rm .env file that may contain sensetive data
rm --verbose .env
