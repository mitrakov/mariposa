#!/usr/bin/env python3

import sys
import re
import json
from typing import Dict, Any, Optional
import requests
from bs4 import BeautifulSoup

# Configuración de cabeceras para evadir el firewall (WAF)
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Connection': 'keep-alive',
    'Cache-Control': 'max-age=0'
}

FIELD_MAP = {
    'Реестровый номер извещения': 'registry_number',
    'Способ осуществления закупки': 'procurement_method',
    'Наименование закупки': 'procurement_name',
    'Редакция': 'revision',
    'Дата размещения извещения': 'notice_date',
    'Дата размещения текущей редакции извещения': 'current_revision_date',
    'Наименование организации': 'customer_full_name',
    'ИНН': 'inn',
    'КПП': 'kpp',
    'ОГРН': 'ogrn',
    'Место нахождения': 'location',
    'Почтовый адрес': 'postal_address',
    'Контактное лицо': 'contact_person',
    'Адрес электронной почты': 'contact_email',
    'Контактный телефон': 'contact_phone',
}

def extract_text(el) -> Optional[str]:
    return el.get_text(strip=True) if el else None

def extract_price(text: str) -> Optional[float]:
    if not text: return None
    cleaned = re.sub(r'[^\d,.]', '', text).replace(',', '.')
    try: return float(cleaned)
    except ValueError: return None

def extract_utc_offset(tz_text: str) -> Optional[str]:
    """Extrae la compensación ISO (ej. '+09:00') desde una cadena tipo 'UTC+9' o 'UTC-3.5'."""
    if not tz_text: return None
    match = re.search(r'UTC([+-]\d+(?:\.\d+)?)', tz_text)
    if match:
        hours_val = float(match.group(1))
        sign = "+" if hours_val >= 0 else "-"
        hours = int(abs(hours_val))
        minutes = int((abs(hours_val) - hours) * 60)
        return f"{sign}{hours:02d}:{minutes:02d}"
    return None

def parse_html(html_content: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html_content, 'lxml')
    data = {}

    # ---- 1. Bloque de Huso Horario (Time Zone) ----
    tz_block = soup.find('div', class_='time-zone')
    if tz_block:
        tz_val = tz_block.find('div', class_='time-zone__value')
        if tz_val:
            tz_text = extract_text(tz_val)
            data['time_zone'] = tz_text
            data['utc_offset'] = extract_utc_offset(tz_text)

    # ---- 2. Bloque de resumen principal (Top form) ----
    entry = soup.find('div', class_='registry-entry__form')
    if entry:
        num = entry.find('div', class_='registry-entry__header-mid__number')
        if num: data['registry_number'] = extract_text(num).replace('№', '').strip()

        status = entry.find('div', class_='registry-entry__header-mid__title')
        if status: data['status'] = extract_text(status)

        for block in entry.find_all('div', class_='registry-entry__body-block'):
            title = block.find('div', class_='registry-entry__body-title')
            value = block.find('div', class_='registry-entry__body-value')
            if title and value:
                if extract_text(title) == 'Объект закупки':
                    data['object_description'] = extract_text(value)
                elif extract_text(title) == 'Заказчик':
                    link = value.find('a')
                    data['customer_name'] = extract_text(link) if link else extract_text(value)

        price_block = entry.find('div', class_='price-block')
        if price_block:
            price_val = price_block.find('div', class_='price-block__value')
            if price_val: data['price'] = extract_price(extract_text(price_val))

        for db in entry.find_all('div', class_='data-block'):
            t, v = db.find('div', class_='data-block__title'), db.find('div', class_='data-block__value')
            if t and v:
                if extract_text(t) == 'Размещено': data['published_date'] = extract_text(v)
                elif extract_text(t) == 'Обновлено': data['updated_date'] = extract_text(v)

    # ---- 3. Bloques detallados iterativos ----
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

    # ---- 4. Mapear datos crudos a llaves finales ----
    for r_key, r_value in raw_fields.items():
        clean_key = r_key.rstrip(':').strip()
        if clean_key in FIELD_MAP:
            data[FIELD_MAP[clean_key]] = r_value

    return data

def main():
    reg_number = sys.argv[1] if len(sys.argv) > 1 else "32616155614"
    url = f"https://zakupki.gov.ru/223/purchase/public/purchase/info/common-info.html?regNumber={reg_number}"
    
    
    try:
        response = requests.get(url, headers=HEADERS, timeout=15)
        response.raise_for_status()
        response.encoding = 'utf-8'
        
        scraped_data = parse_html(response.text)
        print(json.dumps(scraped_data, ensure_ascii=False, indent=4))
        
    except requests.RequestException as e:
        print(json.dumps({"error": f"Fallo al conectar con el servidor: {str(e)}"}, ensure_ascii=False))

if __name__ == '__main__':
    main()
