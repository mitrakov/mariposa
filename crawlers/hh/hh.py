#!/usr/bin/env python3
"""
Simple hh.ru scraper that pushes related vacancies to Kafka.

./hh.py --topic temp-topic --kafka-config sasl.py.properties --current-id-file id.txt

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
from configparser import ConfigParser
from confluent_kafka import Producer

def parse_args():
    parser = ArgumentParser(description="Scrape hh.ru and push to Kafka")
    parser.add_argument("--topic", required=True, help="Kafka topic to publish to")
    parser.add_argument("--kafka-config", required=True, help="Kafka properties file")
    parser.add_argument("--current-id-file", required=True, help="File holding current vacancy ID")
    parser.add_argument("--batch-size", type=int, default=1, help="Number of IDs to process (default: 1)")
    return parser.parse_args()

def load_properties(filepath: str) -> dict[str, str]:
    config = ConfigParser()
    config.optionxform = str           # preserve case
    with open(filepath) as f:
        content = "[root]\n" + f.read()
    config.read_string(content)
    return dict(config.items("root"))

def read_current_id(cur_id_file: str) -> int:
    if os.path.exists(cur_id_file):
        with open(cur_id_file, 'r') as f:
            content = f.read().strip()
            if content:
                return int(content)
    return -1

def write_current_id(cur_id_file: str, cur_id: int):
    with open(cur_id_file, 'w') as f:
        f.write(str(cur_id))

def make_request(vacancy_id: int) -> tuple[list[dict[str, object]], bool]:
    url = f"https://hh.ru/shards/vacancy/related_vacancies?vacancyId={vacancy_id}"
    try:
        resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"})
        if resp.status_code == 404:
            print(f"Vacancy ID {vacancy_id} not found (404).")
            return [], False
        resp.raise_for_status()    # throw for 4xx,5xx errors
        data = resp.json()
        return data.get("vacancies", []), True
    except Exception as e:
        print(f"Failed to fetch {url}: {e}")
        return [], False

def extract_message(vacancy: dict) -> dict:
    company = vacancy.get("company", {})
    address = vacancy.get("address", {})
    reviews = company.get("employerReviews", {})
    compensation = vacancy.get("compensation", {})
    area = vacancy.get("area", {})
    snippet = vacancy.get("snippet", {})
    
    return {
        "vacancyId": vacancy.get("vacancyId"),
        "name": vacancy.get("name"),
        "created": vacancy.get("creationTime"),
        "published": vacancy.get("publicationTime", {}).get("$"),
        "schedule": vacancy.get("@workSchedule"),
        "experience": vacancy.get("workExperience"),
        "employment": vacancy.get("employmentForm"),
        "userTest": vacancy.get("userTestPresent"),
        "internship": vacancy.get("internship"),
        "nightShifts": vacancy.get("nightShifts"),
        "acceptLaborContract": vacancy.get("acceptLaborContract"),
        "workFormats": next((t.get("workFormatsElement")           for t in vacancy.get("workFormats", [])), None),
        "workingHours": next((t.get("workingHoursElement")         for t in vacancy.get("workingHours", [])), None),
        "scheduleByDays": next((t.get("workScheduleByDaysElement") for t in vacancy.get("workScheduleByDays", [])), None),
        "experimental": next((t.get("experimentalMode")            for t in vacancy.get("experimentalModes", [])), None),
        "responses": vacancy.get("responsesCount"),
        "responsesTotal": vacancy.get("totalResponsesCount"),
        "companyName": company.get("name"),
        "companyId": company.get("id"),
        "companyCategory": company.get("@category"),
        "companyURL": company.get("companySiteUrl"),
        "companyAcc": company.get("accreditedITEmployer"),
        "companyReviews": reviews.get("totalRating"),
        "companyReviewsCnt": reviews.get("reviewsCount"),
        "address": address.get("displayName"),
        "district": address.get("districtDto", {}).get("name"),
        "metro": next((t.get("name") for t in address.get("metroStations", {}).get("metro", [])), None),
        "salaryFrom": compensation.get("from"),
        "salaryTo": compensation.get("to"),
        "salaryCurrency": compensation.get("currencyCode"),
        "salaryGross": compensation.get("gross"),
        "salaryPerModeFrom": compensation.get("perModeFrom"),
        "salaryPerModeTo": compensation.get("perModeTo"),
        "salaryMode": compensation.get("mode"),
        "salaryFrequency": compensation.get("frequency"),
        "areaId": area.get("@id"),
        "areaName": area.get("name"),
        "snippetReq": snippet.get("req"),
        "snippetResp": snippet.get("resp"),
        "snippetCond": snippet.get("cond"),
        "snippetSkill": snippet.get("skill"),
    }

def delivery_callback(err, msg, vacancy_id: int, file_for_id: str):
    if err:
        print(f"❌ Failed to send vacancy {vacancy_id} to {msg.topic()}: {err}")
    else:
        write_current_id(file_for_id, vacancy_id + 1)
        print(f"Vacancy {vacancy_id} delivered to {msg.topic()} [partition {msg.partition()}] at offset {msg.offset()}")

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
    kafka_conf = {str(k): str(v) for k, v in kafka_conf.items()}  # convert all k & v to strings
    print(f"Kafka config: {kafka_conf}")

    producer = Producer(kafka_conf)

    err_count = 0                                 # simple circuit-breaker
    for vac_id in range(cur_id, cur_id + args.batch_size):
        print(f"\n\n\nProcessing vacancy ID {vac_id}")
        vacancies, ok = make_request(vac_id)

        if not ok:
            err_count += 1
            if err_count >= 10:
                print("Too many errors to call API. Exiting...")
                break
        else:
            err_count = 0

        for vacancy in vacancies:
            msg = extract_message(vacancy)
            msg.update({"_apiVacancyID": vac_id, "_captureDate": datetime.now().isoformat()})
            payload = json.dumps(msg, ensure_ascii=False)
            print(f"\nSending to Kafka: {payload}")
            producer.produce(args.topic, key=None, value=payload.encode("utf-8"),  # queue msg to producer (async, run in background)
                callback=lambda e, m, v=vac_id, f=args.current_id_file: delivery_callback(e, m, v, f))

        producer.poll(0)                          # process callbacks

        if vac_id < cur_id + args.batch_size - 1: # all but last
            time.sleep(3)                         # sleep 3 sec to respect the server

    producer.flush()                              # block until done
    print("Done!")

if __name__ == "__main__":
    main()
