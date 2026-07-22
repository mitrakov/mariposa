#!/usr/bin/env bash

sleep 220
/home/hadoop/spark-planet-import.sh
sleep 120
/home/hadoop/spark-hh-import.sh
sleep 120
/home/hadoop/spark-fz223-import.sh
