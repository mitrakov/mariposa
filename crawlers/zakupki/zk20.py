#!/usr/bin/env python3

import sys
import re
import json
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional
import requests
from bs4 import BeautifulSoup

# Headers to perfectly mimic a real browser request and bypass WAF blocks
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Connection': 'keep-alive'
}

# Accurate data mapping for 44-FZ sections
FIELD_MAP = {
    'Способ определения поставщика (подрядчика, исполнителя)': 'procurement_method',
    'Наименование электронной площадки': 'electronic_platform_name',
    'Адрес электронной площадки в информационно-телекоммуникационной сети «Интернет»': 'website',
    'Наименование объекта закупки': 'procurement_name',
    'Организация, осуществляющая размещение': 'customer_full_name',
    'Почтовый адрес': 'postal_address',
    'Ответственное должностное лицо': 'contact_person',
    'Адрес электронной почты': 'contact_email',
    'Номер контактного телефона': 'contact_phone',
    'Факс': 'contact_fax',
    'Регион': 'region',
    'Начальная (максимальная) цена контракта': 'start_max_price',
    'Валюта': 'currency',
    'Идентификационный код закупки (ИКЗ)': 'ikz_code',
    'Дата начала исполнения контракта': 'start_date',
    'Срок исполнения контракта': 'deadline',
    'Закупка за счет собственных средств организации': 'contractor_pays',
    'Требуется обеспечение заявки': 'supply_app',
    'Размер обеспечения заявки': 'supply_app_price',
    'Требуется обеспечение исполнения контракта': 'supply_contract',
    'Размер обеспечения исполнения контракта': 'supply_contract_price',
}

# Date and timestamp identification keys
DATE_MAP = {
    'Дата и время начала срока подачи заявок': 'submission_start_datetime',
    'Дата и время окончания срока подачи заявок': 'submission_end_datetime',
    'Дата подведения итогов определения поставщика (подрядчика, исполнителя)': 'results_date',
}


def extract_text(el) -> Optional[str]:
    if not el: 
        return None
    
    text = el.get_text()
    text = text.replace('\xa0', ' ').strip()
    clean_text = re.sub(r'\s+', ' ', text)
    
    return clean_text if clean_text else None



def extract_price(text: str) -> Optional[float]:
    if not text: return None
    cleaned = re.sub(r'[^\d,.]', '', text).replace(',', '.')
    try: return float(cleaned)
    except ValueError: return None


def parse_tz_offset(html_soup: BeautifulSoup) -> timezone:
    """Detects UTC offsets dynamically (e.g. 'UTC+3' -> +03:00 timezone context)."""
    tz_block = html_soup.find('div', class_='time-zone')
    if tz_block:
        tz_val = tz_block.find('div', class_='time-zone__value')
        if tz_val:
            match = re.search(r'UTC([+-]\d+)', extract_text(tz_val))
            if match:
                offset_hours = int(match.group(1))
                return timezone(timedelta(hours=offset_hours))
    return timezone(timedelta(hours=3))  # Safe fallback to Moscow time


def parse_iso_datetime(date_raw_str: Optional[str], tz_info: timezone) -> Optional[str]:
    """Converts strings like '06.07.2026 10:00 (МСК)' or '08.07.2026' into ISO 8601 strings."""
    if not date_raw_str: return None
    
    # Strip any appended Russian abbreviations like (МСК)
    clean_str = re.sub(r'\(.*?\)', '', date_raw_str).strip()
    
    # Check Strategy 1: Has hour and minute configuration
    try:
        dt = datetime.strptime(clean_str, "%d.%m.%Y %H:%M")
        return dt.replace(tzinfo=tz_info).isoformat()
    except ValueError:
        pass

    # Check Strategy 2: Pure Calendar Date Configuration
    try:
        dt = datetime.strptime(clean_str, "%d.%m.%Y")
        return dt.replace(tzinfo=tz_info).isoformat()
    except ValueError:
        return None


def parse_44fz_html(html_content: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html_content, 'lxml')
    data = {}

    # Extract global timezone context
    tz_info = parse_tz_offset(soup)

    # 1. Parse Top Main Card Summary Block
    main_info = soup.find('div', class_='cardMainInfo')
    if main_info:
        # Purchase ID Number
        p_link = main_info.find('span', class_='cardMainInfo__purchaseLink')
        if p_link: data['registry_number'] = extract_text(p_link).replace('№', '').strip()
        
        # Procurement Card Status State
        p_state = main_info.find('span', class_='cardMainInfo__state')
        if p_state: data['status'] = extract_text(p_state)

        # Basic object definition blocks
        for section in main_info.find_all('div', class_='cardMainInfo__section'):
            title = section.find('span', class_='cardMainInfo__title')
            content = section.find('span', class_='cardMainInfo__content')
            if title and content:
                t_txt = extract_text(title)
                if t_txt == 'Объект закупки':
                    data['object_description'] = extract_text(content)
                elif t_txt == 'Заказчик':
                    link = content.find('a')
                    data['customer_name'] = extract_text(link) if link else extract_text(content)
                elif t_txt == 'Размещено':
                    data['published_date'] = parse_iso_datetime(extract_text(content), tz_info)
                elif t_txt == 'Обновлено':
                    data['updated_date'] = parse_iso_datetime(extract_text(content), tz_info)
                elif t_txt == 'Окончание подачи заявок':
                    data['submission_deadline'] = parse_iso_datetime(extract_text(content), tz_info)

        # Direct Price Processing
        price_el = main_info.find('span', class_='cost')
        if price_el: data['price'] = extract_price(extract_text(price_el))

    # 2. Parse Detailed Content Section Blocks
    for section in soup.find_all('section', class_='blockInfo__section'):
        title_el = section.find('span', class_='section__title')
        info_el = section.find('span', class_='section__info')
        
        if title_el and info_el:
            t_txt = extract_text(title_el).rstrip(':').strip()
            i_txt = extract_text(info_el)
            
            # Map standard descriptive properties
            if t_txt in FIELD_MAP:
                data[FIELD_MAP[t_txt]] = i_txt
            
            # Map complex dynamic process datetimes
            elif t_txt in DATE_MAP:
                data[DATE_MAP[t_txt]] = parse_iso_datetime(i_txt, tz_info)

    return data


def main():
    # Flexible execution parameter (Accepts sys parameter or defaults to your exact example ID)
    reg_number = sys.argv[1] if len(sys.argv) > 1 else "0373200637326000025"
    url = f"https://zakupki.gov.ru/epz/order/notice/zk20/view/common-info.html?regNumber={reg_number}"
    
    try:
        # Perform dynamic curl-equivalent request
        response = requests.get(url, headers=HEADERS, timeout=15)
        response.raise_for_status()
        response.encoding = 'utf-8'
        
        # Process and Output formatted JSON
        result_json = parse_44fz_html(response.text)
        print(json.dumps(result_json, ensure_ascii=False, indent=4))

    except requests.RequestException as e:
        print(json.dumps({"error": f"Failed to retrieve data from network source: {str(e)}"}))


if __name__ == '__main__':
    main()
