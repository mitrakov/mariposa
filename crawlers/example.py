#!/usr/bin/env python3
"""
Simple scraper that makes http requests in a loop and pushes json messages to Kafka.

./example.py --topic temp-topic --kafka-config sasl.py.properties --current-id-file id.txt

properties file example:
bootstrap.servers=$(hostname):9092
security.protocol=SASL_SSL
ssl.ca.location=/opt/vault/certs/root_ca.crt
sasl.kerberos.principal=hadoop/$(hostname)@MARIPOSA.COM
sasl.kerberos.keytab=/etc/security/keytabs/$(hostname).keytab
"""

import os
import json
import time
import requests
from datetime import datetime
from argparse import ArgumentParser
from confluent_kafka import Producer
from configparser import ConfigParser


# parses cmd line arguments
def parse_args():
    parser = ArgumentParser(description="Scrape hh.ru and push to Kafka")
    parser.add_argument("--topic", required=True, help="Kafka topic to publish to")
    parser.add_argument("--kafka-config", required=True, help="Kafka properties file")
    parser.add_argument("--current-id-file", required=True, help="File holding current vacancy ID")
    parser.add_argument("--batch-size", type=int, default=1, help="Number of IDs to process (default: 1)")
    return parser.parse_args()


# loads properties for Apache Kafka
def load_properties(filepath: str) -> dict[str, str]:
    config = ConfigParser()
    config.optionxform = str           # preserve case
    with open(filepath) as f:
        content = "[root]\n" + f.read()
    config.read_string(content)
    return dict(config.items("root"))


# reads current ID from a simple text file (in Prod, use more robust tools)
def read_current_id(cur_id_file: str) -> int:
    if os.path.exists(cur_id_file):
        with open(cur_id_file, 'r') as f:
            content = f.read().strip()
            if content:
                return int(content)
    return -1


# writes current ID to a simple text file (in Prod, use more robust tools)
def write_current_id(cur_id_file: str, cur_id: int):
    with open(cur_id_file, 'w') as f:
        f.write(str(cur_id))


# makes an HTTP request to data source web-site; returns tuple {List[Json]; Error}
def make_request(id: int) -> tuple[list[dict[str, object]], bool]:
    url = f"https://hh.ru/shards/vacancy/related_vacancies?vacancyId={id}"
    try:
        resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"})
        if resp.status_code == 404:
            print(f"Not found: {id} (404).")
            return [], False
        resp.raise_for_status()    # throw for 4xx,5xx errors
        data = resp.json()
        return data.get("vacancies", []), True
    except Exception as e:
        print(f"Failed to fetch {url}: {e}")
        return [], False


# extracts data from json and makes a new json for Apache Kafka; add your logic here
def extract_message(vacancy: dict) -> dict:
    metro = vacancy.get("metroStations", {}).get("metro", [])
    return {
        "id":    vacancy.get("vacancyId"),
        "name":  vacancy.get("name"),
        "metro": next((t.get("name") for t in metro), None),     # gets first element of array, or None
    }


# callback for Kafka Producer
def delivery_callback(err, msg, id: int, file_for_id: str):
    if err:
        print(f"❌ Failed to send {id} to {msg.topic()}: {err}")
    else:
        write_current_id(file_for_id, id + 1)            # write a new ID into a text file
        print(f"Item {id} delivered to {msg.topic()} [partition {msg.partition()}] at offset {msg.offset()}")


# main
def main():
    args = parse_args()

    if not os.path.exists(args.kafka_config):
        print(f"Config file not found: {args.kafka_config}")
        return

    if not os.path.exists(args.current_id_file):
        print(f"File holding the ID not found: {args.current_id_file}")
        return

    cur_id = read_current_id(args.current_id_file)
    if cur_id < 0:
        print("Invalid file with current ID")
        return

    kafka_conf = load_properties(args.kafka_config)
    kafka_conf = {str(k): str(v) for k, v in kafka_conf.items()}  # converts all keys & values to strings to avoid issues
    print(f"Kafka config: {kafka_conf}")

    producer = Producer(kafka_conf)

    err_count = 0
    for vac_id in range(cur_id, cur_id + args.batch_size):        # main loop
        print(f"\n\n\nProcessing ID {vac_id}")
        vacancies, ok = make_request(vac_id)

        if not ok:
            err_count += 1
            if err_count >= 10:                                   # simple circuit-breaker
                print("Too many errors to call API. Exiting...")
                break
        else:
            err_count = 0                                         # reset circuit-breaker

        # process each message, convert to Json and push to Kafka topic
        for vacancy in vacancies:
            msg = extract_message(vacancy)
            msg.update({"api_vacancy_id": vac_id, "api_capture_date": datetime.now().isoformat()})   # add extra data for tracking
            payload = json.dumps(msg, ensure_ascii=False)                                            # convert dict to a real json
            print(f"\nSending to Kafka: {payload}")
            producer.produce(args.topic, key=None, value=payload.encode("utf-8"),  # queue msg to producer (async, run in background)
                callback=lambda e, m, v=vac_id, f=args.current_id_file: delivery_callback(e, m, v, f))

        producer.poll(0)                          # process callbacks (in 0 seconds)
        time.sleep(3)                             # sleep N sec to respect the server

    producer.flush()                              # block until done
    print("Done!")


# entry point
if __name__ == "__main__":
    main()
