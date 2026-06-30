import re
import json
import time
import requests
from bs4 import BeautifulSoup
from kafka import KafkaProducer

# === CONFIGURACIÓN DE KAFKA ===
KAFKA_BROKERS = ['localhost:9092']
KAFKA_TOPIC = 'loveplanet_profiles'

# Inicializar el productor de Kafka
# producer = KafkaProducer(
#     bootstrap_servers=KAFKA_BROKERS,
#     value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode('utf-8')
# )

# === CONFIGURACIÓN DEL RASPADOR ===
DOMAIN = "https://loveplanet.ru"
SEARCH_URL_PATTERN = DOMAIN + "/a-search/d-1/p-{page}"
LINK_PATTERN = re.compile(r"^/page/\w+/frl-2$")

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
}

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
        "отношения": "relationship_status",
        "дети": "children",
        "домашние_животные": "pets",
        "жилищные_условия": "housing_conditions",
        "наличие_автомобиля": "has_car",
        "образование": "education",
        "доход": "income",
        "сфера_деятельности": "industry",
        "должность": "job_title",
        "курение": "smoking",
        "алкоголь": "alcohol",
        "знание_языков": "languages",
        "спорт": "sports",
        "ваше_образование": "your_education",
        "любимая_музыка": "favorite_music",
        "любимые_фильмы": "favorite_movies",
        "любимые_книги": "favorite_books",
        "любимые_блюда": "favorite_dishes",
        "самое_хорошее_в_жизни": "best_thing_in_life",
        "самое_ужасное_в_жизни": "worst_thing_in_life",
        "какие_качества_вы_цените_в_людях": "valued_qualities_in_people",
        
        # FIXED: Removed the comma so it catches the normalized key string perfectly
        "что_вы_могли_бы_простить_а_что_нет": "what_can_you_forgive",
        
        "ваши_достоинства": "your_strengths",
        "ваши_недостатки": "your_weaknesses",
        "чем_интересна_ваша_работа": "why_job_is_interesting",
        "самый_авантюрный_поступок": "most_adventurous_act",
        "что_вам_нравится_или_не_нравится_в_телевизоре": "tv_opinions",
        "как_вы_относитесь_к_мату": "opinion_on_profanity",
        "любимые_города_и_страны": "favorite_cities_and_countries",
        "любимые_места": "favorite_places",
        "какое_место_занимает_в_вашей_жизни_религия": "religion_importance"
    }
    
    normalized_key = raw_key.lower().strip().replace(' ', '_')
    normalized_key = re.sub(r'[^a-z0-9_а-яё]', '', normalized_key)
    
    if normalized_key in translations:
        return f"{prefix}_{translations[normalized_key]}"
    else:
        return f"{prefix}_{transliterate_to_ascii(normalized_key)}"



def flatten_profile(raw_data):
    """Flattens the nested dictionary into a single-level structure with Hive-compatible keys."""
    flat_data = {
        "display_name_age": raw_data["display_name_age"],
        "main_photo_url": raw_data["main_photo_url"],
        "city": raw_data["city"],
        "current_visitors": raw_data["current_visitors"],
        "status_quote": raw_data["status_quote"],
        "seeking": raw_data["seeking"],
        "about_self": raw_data["about_self"],
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

def parse_profile_page(profile_url):
    """Fetches individual profile page and pulls raw structured values using None as fallback."""
    try:
        response = requests.get(profile_url, headers=HEADERS, timeout=10)
        if response.status_code != 200:
            print(f"   Failed to fetch profile: {profile_url} (Status: {response.status_code})")
            return None
        
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
            "display_name_age": display_name,
            "main_photo_url": main_photo_url,
            "city": city,
            "current_visitors": visitors_count,
            "status_quote": status_text,
            "interests": interests,
            "seeking": seeking_text,
            "about_self": about_text,
            "target_search": target_search_text,
            "personal_details": personal_info,
            "self_portrait": self_portrait,
            "profile_url": profile_url
        }

    except requests.exceptions.RequestException as e:
        print(f"   Network error on subpage {profile_url}: {e}")
        return None


def main_scraper():
    print(f"🚀 Iniciando Streaming a Kafka en el tópico: '{KAFKA_TOPIC}'...")

    for page in range(0, 1001):
        search_url = SEARCH_URL_PATTERN.format(page=page)
        print(f"\n--- Scraping Index Page {page} ---")
        
        try:
            response = requests.get(search_url, headers=HEADERS, timeout=10)
            if response.status_code != 200:
                print(f"Skipping directory page {page}: Status {response.status_code}")
                continue
                
            soup = BeautifulSoup(response.text, 'html.parser')
            containers = soup.find_all('div', class_='buser_usinfo')
            
            for container in containers:
                link_tag = container.find('a', class_='buser_usname', href=True)
                if link_tag and LINK_PATTERN.match(link_tag['href']):
                    full_profile_url = DOMAIN + link_tag['href']
                    
                    print(f" -> Processing profile: {full_profile_url}")
                    profile_data = parse_profile_page(full_profile_url)
                    
                    if profile_data:
                        # 1. Aplanar el diccionario antes de enviarlo
                        flattened_data = flatten_profile(profile_data)
                        
                        # 2. Transmitir el evento directamente a Kafka
                        ##producer.send(KAFKA_TOPIC, value=flattened_data)
                        print(f"    Evento enviado a Kafka para: {json.dumps(flattened_data, ensure_ascii=False)}")
                    
                    time.sleep(1.5)
                    
        except requests.exceptions.RequestException as e:
            print(f"Network error on index {page}: {e}")
            
        time.sleep(1)
        
        # Forzar el envío de los mensajes acumulados en el buffer antes de pasar a la siguiente página
        #producer.flush()

    # Cerrar el productor de forma limpia al terminar las 1000 páginas
    #producer.close()
    print("\n Transmission complete. Kafka Producer closed successfully.")

if __name__ == "__main__":
    main_scraper()
