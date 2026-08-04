#!/usr/bin/env bash
set -euo pipefail
source .env

# add your app code here
echo "Hello world"

# optional: rm .env file that may contain sensetive data
rm --verbose .env
