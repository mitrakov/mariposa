#!/usr/bin/env python3

"""
Simple loveplanet.ru scraper that pushes users' profiles to Kafka.

./planet.py --topic planet-import --kafka-config kafka.properties

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
from datetime import datetime
from bs4 import BeautifulSoup
from argparse import ArgumentParser
from confluent_kafka import Producer
from configparser import ConfigParser


# parses cmd line arguments
def parse_args():
    parser = ArgumentParser(description="Scrape hh.ru and push to Kafka")
    parser.add_argument("--topic", required=True, help="Kafka topic to publish to")
    parser.add_argument("--kafka-config", required=True, help="Kafka properties file")
    return parser.parse_args()


# loads properties for Apache Kafka
def load_properties(filepath: str) -> dict[str, str]:
    config = ConfigParser()
    config.optionxform = str           # preserve case
    with open(filepath) as f:
        content = "[root]\n" + f.read()
    config.read_string(content)
    return dict(config.items("root"))


def transliterate_to_ascii(text):
    """Translitera caracteres cirílicos a texto ASCII plano y limpio."""
    cyrillic_translit = {
        'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', 
        'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 
        'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 
        'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 
        'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya'
    }
    # Convertir a minúsculas, reemplazar espacios por guiones bajos
    text = text.lower().strip().replace(' ', '_')
    # Eliminar puntuación común que Hive rechaza en columnas
    text = re.sub(r'[^a-z0-9_а-яё]', '', text)
    
    # Aplicar transliteración carácter por carácter
    res = []
    for char in text:
        res.append(cyrillic_translit.get(char, char))
    return ''.join(res)


def clean_hive_key(prefix, raw_key):
    """Translates common keys or applies transliteration as a fallback for Hive."""
    translations = {
        "внешность": "appearance",
        "отношения": "status",
        "дети": "children",
        "домашние_животные": "pets",
        "жилищные_условия": "housing",
        "наличие_автомобиля": "has_car",
        "образование": "education",
        "учебное_заведение": "university",
        "год_выпуска": "graduate_year",
        "доход": "income",
        "сфера_деятельности": "industry",
        "должность": "job",
        "курение": "smoking",
        "алкоголь": "alcohol",
        "знание_языков": "languages",
        "спорт": "sports",
        "ваше_образование": "education",
        "любимая_музыка": "favorite_music",
        "любимые_фильмы": "favorite_movies",
        "любимые_книги": "favorite_books",
        "любимые_блюда": "favorite_dishes",
        "самое_хорошее_в_жизни": "best_thing",
        "самое_ужасное_в_жизни": "worst_thing",
        "какие_качества_вы_цените_в_людях": "valued_qualities",
        "что_вы_могли_бы_простить_а_что_нет": "what_forgive",
        "ваши_достоинства": "strengths",
        "ваши_недостатки": "weaknesses",
        "чем_интересна_ваша_работа": "job_interesting",
        "самый_авантюрный_поступок": "adventure",
        "что_вам_нравится_или_не_нравится_в_телевизоре": "tv",
        "как_вы_относитесь_к_мату": "profanity",
        "любимые_города_и_страны": "favorite_cities",
        "любимые_места": "favorite_places",
        "любимые_занятия": "favorite_hobby",
        "какое_место_занимает_в_вашей_жизни_религия": "religion"
    }
    
    normalized_key = raw_key.lower().strip().replace(' ', '_')
    normalized_key = re.sub(r'[^a-z0-9_а-яё]', '', normalized_key)
    
    if normalized_key in translations:
        return f"{prefix}_{translations[normalized_key]}"
    else:
        return f"{prefix}_{transliterate_to_ascii(normalized_key)}"



def flatten_profile(raw_data: dict[str, object]) -> dict[str, object]:
    """Flattens the nested dictionary into a single-level structure with Hive-compatible keys."""
    flat_data = {
        "name_age": raw_data["name_age"],
        "photo_url": raw_data["photo_url"],
        "city": raw_data["city"],
        "visitors": raw_data["visitors"],
        "quote": raw_data["quote"],
        "seeking": raw_data["seeking"],
        "about": raw_data["about"],
        "target_search": raw_data["target_search"],
        "profile_url": raw_data["profile_url"],
        "interests": raw_data["interests"] if raw_data["interests"] else []
    }
    
    # Flatten Personal Details block
    for key, val in raw_data["personal_details"].items():
        flat_key = clean_hive_key("personal", key)
        flat_data[flat_key] = val
            
    # Guarantee critical array keys default to an empty list instead of None
    if "personal_languages" not in flat_data:
        flat_data["personal_languages"] = []
    if "personal_sports" not in flat_data:
        flat_data["personal_sports"] = []
        
    # Flatten Self Portrait block
    for key, val in raw_data["self_portrait"].items():
        flat_key = clean_hive_key("portrait", key)
        flat_data[flat_key] = val
        
    return flat_data


def parse_profile_page(profile_url: str) -> dict[str, object]:
    """Fetches individual profile page and pulls raw structured values using None as fallback."""
    try:
        response = requests.get(profile_url, headers={"User-Agent": "Mozilla/5.0"})
        if response.status_code != 200:
            print(f"Failed to fetch profile: {profile_url} (Status: {response.status_code})")
            return None
        response.raise_for_status()    # throw for 4xx,5xx errors
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 1. Name & Age
        name_age_tag = soup.find('span', class_='fbold fsize20')
        display_name = name_age_tag.get_text(strip=True) if name_age_tag else None
        
        # 2. Main Photo
        main_photo_url = None
        photo_container = soup.find('div', class_=re.compile(r'prof-photo'))
        if photo_container:
            img_tag = photo_container.find('img')
            if img_tag and img_tag.has_attr('src'):
                main_photo_url = img_tag['src']
        
        # 3. City & Live Traffic Count
        city = None
        visitors_count = 0
        location_box = soup.find('div', class_='blue_14')
        if location_box:
            city_span = location_box.find('span')
            if city_span:
                city = city_span.get_text(strip=True)
            
            visitors_div = location_box.find('div', class_=re.compile(r'visiters|blue_g'))
            if visitors_div:
                visitors_text = visitors_div.get_text(strip=True)
                if visitors_text.isdigit():
                    visitors_count = int(visitors_text)
                    
        # 4. Profile Quote Status Line
        status_text = None
        status_div = soup.find('div', class_=re.compile(r'prof-status'))
        if status_div:
            status_text = status_div.get_text(strip=True)
        
        # 5. Interests Cloud Array
        interests = []
        tag_container = soup.find('div', id='tag-container')
        if tag_container:
            tag_links = tag_container.find_all('a')
            interests = [tag.get_text(strip=True) for tag in tag_links if tag.get_text(strip=True)]
        
        # 6. Seeking Paragraph Block
        seeking_title = soup.find('div', string=re.compile("Я ищу", re.IGNORECASE))
        seeking_text = None
        if seeking_title:
            seeking_ul = seeking_title.find_next_sibling('ul')
            if seeking_ul:
                seeking_text = seeking_ul.get_text(strip=True)
                
        # 7. About Self Paragraph Block
        about_title = soup.find('div', string=re.compile("Свободно о себе", re.IGNORECASE))
        about_text = None
        if about_title:
            about_ul = about_title.find_next_sibling('ul')
            if about_ul:
                about_text = about_ul.get_text(strip=True)

        # 8. Target Search Paragraph Block
        target_title = soup.find('div', string=re.compile("Ккого я хочу найти", re.IGNORECASE))
        if not target_title:
            target_title = soup.find('div', string=re.compile("Кого я хочу найти", re.IGNORECASE))
        target_search_text = None
        if target_title:
            target_ul = target_title.find_next_sibling('ul')
            if target_ul:
                target_search_text = target_ul.get_text(strip=True)

        # 9. Personal Info List Map
        personal_info = {}
        info_section = soup.find('div', string=re.compile("Личная информация", re.IGNORECASE))
        if info_section:
            info_ul = info_section.find_next_sibling('ul', class_='list_info')
            if info_ul:
                for li in info_ul.find_all('li', class_='flex'):
                    label_tag = li.find('label')
                    if label_tag:
                        label_key = label_tag.get_text(strip=True).rstrip(':')
                        sport_box = li.find('div', class_='xcloud-box')
                        if sport_box:
                            value = [span.get_text(strip=True) for span in sport_box.find_all('span')]
                        else:
                            val_div = li.find('div')
                            value = val_div.get_text(strip=True) if val_div else None
                        personal_info[label_key] = value

        # 10. Self Portrait Info List Map
        self_portrait = {}
        portrait_section = soup.find('div', string=re.compile("Автопортрет", re.IGNORECASE))
        if portrait_section:
            portrait_ul = portrait_section.find_next_sibling('ul', class_='list_info')
            if portrait_ul:
                for li in portrait_ul.find_all('li', class_='flex'):
                    label_tag = li.find('label')
                    if label_tag:
                        label_key = label_tag.get_text(strip=True).rstrip(':')
                        val_div = li.find('div')
                        value = val_div.get_text(strip=True) if val_div else None
                        self_portrait[label_key] = value

        return {
            "name_age": display_name,
            "photo_url": main_photo_url,
            "city": city,
            "visitors": visitors_count,
            "quote": status_text,
            "interests": interests,
            "seeking": seeking_text,
            "about": about_text,
            "target_search": target_search_text,
            "personal_details": personal_info,
            "self_portrait": self_portrait,
            "profile_url": profile_url
        }
    except Exception as e:
        print(f"Error on subpage {profile_url}: {e}")
        return None


# callback for Kafka Producer
def delivery_callback(err, msg, url: str):
    if err:
        print(f"❌ Failed to send {url} to {msg.topic()}: {err}")
    else:
        print(f"Item {url} delivered to {msg.topic()} [partition {msg.partition()}] at offset {msg.offset()}")


def main():
    args = parse_args()

    if not os.path.exists(args.kafka_config):
        print(f"Config file not found: {args.kafka_config}")
        return

    kafka_conf = load_properties(args.kafka_config)
    kafka_conf = {str(k): str(v) for k, v in kafka_conf.items()}  # converts all keys & values to strings to avoid issues
    print(f"Kafka config: {kafka_conf}")

    producer = Producer(kafka_conf)

    for page in range(0, 1001):
        print(f"\n--- Scraping Index Page {page} ---")
        try:
            response = requests.get(f"https://loveplanet.ru/a-search/d-1/p-{page}", headers={"User-Agent": "Mozilla/5.0"})
            if response.status_code == 404:
                print(f"Not found {page}: Status {response.status_code}")
                continue
            response.raise_for_status()    # throw for 4xx,5xx errors
                
            soup = BeautifulSoup(response.text, 'html.parser')
            containers = soup.find_all('div', class_='buser_usinfo')
            
            for container in containers:
                link_tag = container.find('a', class_='buser_usname', href=True)
                if link_tag and re.compile(r"^/page/\w+/frl-2$").match(link_tag['href']):
                    full_profile_url = f"https://loveplanet.ru{link_tag['href']}"
                    
                    print(f"\nProcessing profile: {full_profile_url}")
                    profile_data = parse_profile_page(full_profile_url)
                    
                    if profile_data:
                        msg = flatten_profile(profile_data)
                        msg.update({"api_capture_date": datetime.now().isoformat()})           # add extra data for tracking
                        payload = json.dumps(msg, ensure_ascii=False)                          # convert dict to a real json
                        print(f"Sending to Kafka: {payload}")
                        producer.produce(args.topic, key=None, value=payload.encode("utf-8"),  # queue msg to producer (async, run in background)
                            callback=lambda e, m, v=link_tag['href']: delivery_callback(e, m, v))
                    
                    time.sleep(1.5)               # sleep N sec to respect the server

        except Exception as e:
            print(f"Error on page {page}: {e}")
            
        time.sleep(1)
        producer.flush()

    producer.flush()                              # block until done
    print("Done!")


# entry point
if __name__ == "__main__":
    while True:
        main()
        time.sleep(5 * 60 * 60)    # 5h
