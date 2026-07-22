#!/usr/bin/env python3
"""
Simple scraper for zakupki.gov for 223-FZ.
./fz223.py --topic zakupki-fz223-import --kafka-config kafka.properties --current-id-file id.txt --batch-size 28800

properties file example:
bootstrap.servers=$(hostname):9092
security.protocol=SASL_SSL
ssl.ca.location=/opt/vault/certs/root_ca.crt
sasl.kerberos.principal=hadoop/$(hostname)@MARIPOSA.COM
sasl.kerberos.keytab=/etc/security/keytabs/$(hostname).keytab
"""

import os
import re
import json
import time
import requests
from typing import Dict, Any, Optional
from bs4 import BeautifulSoup
from datetime import datetime
from argparse import ArgumentParser
from configparser import ConfigParser
from confluent_kafka import Producer
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)    # suppress "InsecureRequestWarning: Unverified HTTPS request"


# html field to json-key mapping
FIELD_MAP = {
    'Реестровый номер извещения': 'reg_number',
    'Способ осуществления закупки': 'method',
    'Наименование закупки': 'description',
    'Редакция': 'revision',
    'Дата размещения извещения': 'notice_date',
    'Дата размещения текущей редакции извещения': 'revision_date',
    'Наименование организации': 'customer',
    'ИНН': 'inn',
    'КПП': 'kpp',
    'ОГРН': 'ogrn',
    'Место нахождения': 'location',
    'Почтовый адрес': 'address',
    'Контактное лицо': 'contact_person',
    'Адрес электронной почты': 'contact_email',
    'Контактный телефон': 'contact_phone',
}


# parses cmd line arguments
def parse_args():
    parser = ArgumentParser(description="Scrape zakupki.gov.ru (FZ-233) and push to Kafka")
    parser.add_argument("--topic", required=True, help="Kafka topic to publish to")
    parser.add_argument("--kafka-config", required=True, help="Kafka properties file")
    parser.add_argument("--current-id-file", required=True, help="File holding current Registration Number")
    parser.add_argument("--batch-size", type=int, default=1, help="Number of IDs to process (default: 1)")
    parser.add_argument("--dry-run", type=bool, default=False, help="Skip sending to Kafka")
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
def make_request(reg_number: int) -> tuple[dict[str, Any], bool]:
    url = f"https://zakupki.gov.ru/223/purchase/public/purchase/info/common-info.html?regNumber={reg_number}"
    try:
        resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, verify=False)   # Verify=False to skip shitty МинЦифры certs
        if resp.status_code == 404:
            print(f"Not found: {reg_number} (404).")
            return {}, False
        resp.raise_for_status()    # throw for 4xx,5xx errors

        return parse_html(resp.text), True
    except Exception as e:
        print(f"Failed to fetch {url}: {e}")
        return {}, False


# parsing
def parse_html(html_content: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html_content, 'lxml')
    data = {}

    # timezone block
    tz_block = soup.find('div', class_='time-zone')
    if tz_block:
        tz_val = tz_block.find('div', class_='time-zone__value')
        if tz_val:
            tz_text = extract_text(tz_val)
            data['timezone'] = tz_text

    # top form
    entry = soup.find('div', class_='registry-entry__form')
    if entry:
        status = entry.find('div', class_='registry-entry__header-mid__title')
        if status: data['status'] = extract_text(status)

        price_block = entry.find('div', class_='price-block')
        if price_block:
            price_val = price_block.find('div', class_='price-block__value')
            if price_val: data['price'] = extract_price(extract_text(price_val))

        for t in entry.find_all('div', class_='data-block__title'):
            # get the value element. It's usually the next sibling, or inside the same parent.
            v = t.find_next_sibling('div', class_='data-block__value')
            if not v:
                # fallback: try the parent's sibling or look for it in the same column
                parent_col = t.parent
                if parent_col:
                    v = parent_col.find('div', class_='data-block__value')
            
            if t and v:
                title_text = extract_text(t)
                value_text = extract_text(v)
                
                if title_text == 'Размещено':
                    data['publish_date'] = parse_to_iso_date(value_text)
                elif title_text == 'Обновлено':
                    data['update_date']  = parse_to_iso_date(value_text)
                elif title_text == 'Окончание подачи заявок':
                    data['finish_date']  = parse_to_iso_date(value_text)

    # details block
    raw_fields = {}
    for section in soup.find_all('section', class_='common-text'):
        for row in section.find_all('div', class_='row') or [section]:
            titles = row.find_all('div', class_='common-text__title')
            for title_el in titles:
                val_el = title_el.find_next_sibling('div', class_='common-text__value')
                if val_el: raw_fields[extract_text(title_el)] = extract_text(val_el)
        
        for gray_el in section.find_all('div', class_='common-text__value--gray'):
            label_text = extract_text(gray_el).replace(':', '').strip()
            val_el = gray_el.find_next_sibling('div', class_='common-text__value')
            if val_el: raw_fields[label_text] = extract_text(val_el)

    # final mapping
    for r_key, r_value in raw_fields.items():
        clean_key = r_key.rstrip(':').strip()
        if clean_key in FIELD_MAP:
            data[FIELD_MAP[clean_key]] = r_value
    return data

def extract_text(el) -> Optional[str]:
    return el.get_text(strip=True) if el else None

def extract_price(text: str) -> Optional[float]:
    if not text: return None
    cleaned = re.sub(r'[^\d,.]', '', text).replace(',', '.')
    try: return float(cleaned)
    except ValueError: return None

def parse_to_iso_date(date_text: str) -> Optional[str]:
    if not date_text:
        return None
    try:
        # Convert Russian "18.06.2026" format into clean "2026-06-18" ISO format
        parsed_dt = datetime.strptime(date_text.strip(), "%d.%m.%Y")
        return parsed_dt.strftime("%Y-%m-%d")
    except ValueError:
        return None


# callback function for Kafka Producer
def delivery_callback(err, msg, id: int, file_for_id: str):
    if err:
        print(f"Failed to send ID {id} to {msg.topic()}: {err}")
    else:
        write_current_id(file_for_id, id + 1)            # write a new ID into a text file
        print(f"ID {id} delivered to {msg.topic()} [partition {msg.partition()}] at offset {msg.offset()}")


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
    for id in range(cur_id, cur_id + args.batch_size):            # main loop
        print(f"\n\n\nProcessing Registration Number: {id}")
        data, ok = make_request(id)
        if not "reg_number" in data:                              # skip, if page is empty
            continue;

        if not ok:
            err_count += 1
            if err_count >= 10:                                   # simple circuit-breaker
                print("Too many errors to call API. Exiting...")
                break
        else:
            err_count = 0                                         # reset circuit-breaker

        # convert to Json and push to Kafka topic
        data.update({"api_id": id, "api_capture_date": datetime.now().isoformat()})    # add extra data for tracking
        payload = json.dumps(data, ensure_ascii=False)                                 # convert dict to a real json
        print(f"\nSending to Kafka: {payload}")

        if not args.dry_run:
            producer.produce(args.topic, key=None, value=payload.encode("utf-8"),  # queue msg to producer (async, run in background)
                callback=lambda e, m, v=id, f=args.current_id_file: delivery_callback(e, m, v, f))

        producer.poll(0)                          # process callbacks (in 0 seconds)
        time.sleep(3)                             # sleep 3 sec to respect the server

    producer.flush()                              # block until done
    print("Done!")


# entry point
if __name__ == '__main__':
    main()
