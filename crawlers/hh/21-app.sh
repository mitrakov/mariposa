#!/usr/bin/env bash
set -euo pipefail
source utils.sh
source .env

check_env "JKS_PASSWORD"
export JKS_PASSWORD
(cd /home/hadoop/hh && java -jar mariposa-scraper.jar HhScraper.scala > hh.log 2>&1 &)

rm --verbose .env
