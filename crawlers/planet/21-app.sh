#!/usr/bin/env bash
set -euo pipefail
source utils.sh
source .env

check_env "JKS_PASSWORD"
export JKS_PASSWORD
(cd /home/hadoop/planet && java -jar mariposa-scraper.jar PlanetScraper.scala > planet.log 2>&1 &)

rm --verbose .env
