-- ============================================================================
-- Описание: Структура таблицы профилей LovePlanet для Apache Hive / Spark SQL
-- Формат хранения: Parquet (Колоночное сжатие)
-- ============================================================================

CREATE EXTERNAL TABLE IF NOT EXISTS default.loveplanet_profiles (
    display_name_age                    STRING          COMMENT 'Имя и возраст пользователя (например: Александр, 37)',
    main_photo_url                      STRING          COMMENT 'Прямая ссылка на главную фотографию профиля',
    city                                STRING          COMMENT 'Город проживания пользователя',
    current_visitors                    INT             COMMENT 'Текущее количество онлайн-посетителей на анкете',
    status_quote                        STRING          COMMENT 'Текстовый статус / цитата пользователя',
    seeking                             STRING          COMMENT 'Текст из блока требований к поиску (Я ищу...)',
    about_self                          STRING          COMMENT 'Текст из свободного описания (Свободно о себе)',
    target_search                       STRING          COMMENT 'Текст из блока целей (Кого я хочу найти)',
    profile_url                         STRING          COMMENT 'Полный абсолютный URL-адрес профиля пользователя',
    interests                           ARRAY<STRING>   COMMENT 'Массив тегов интересов пользователя',
    
    -- Блок личной информации (Префикс personal_)
    personal_appearance                 STRING          COMMENT 'Внешние данные (рост, вес, телосложение, цвет глаз)',
    personal_relationship_status        STRING          COMMENT 'Семейное положение / статус отношений',
    personal_children                   STRING          COMMENT 'Отношение к детям и их наличие',
    personal_pets                       STRING          COMMENT 'Наличие домашних животных',
    personal_housing_conditions         STRING          COMMENT 'Жилищные условия пользователя',
    personal_has_car                    STRING          COMMENT 'Наличие личного автомобиля',
    personal_education                  STRING          COMMENT 'Общее образование',
    personal_income                     STRING          COMMENT 'Уровень дохода пользователя',
    personal_industry                   STRING          COMMENT 'Сфера профессиональной деятельности',
    personal_job_title                  STRING          COMMENT 'Конкретная должность пользователя',
    personal_smoking                    STRING          COMMENT 'Отношение к курению',
    personal_alcohol                    STRING          COMMENT 'Отношение к алкоголю',
    personal_languages                  ARRAY<STRING>   COMMENT 'Массив языков, которыми владеет пользователь',
    personal_sports                     ARRAY<STRING>   COMMENT 'Массив видов спорта, которыми занимается пользователь',
    
    -- Блок автопортрета (Префикс portrait_)
    portrait_your_education             STRING          COMMENT 'Детальное описание образования из анкеты',
    portrait_favorite_music             STRING          COMMENT 'Любимые музыкальные жанры и исполнители',
    portrait_favorite_movies            STRING          COMMENT 'Любимые фильмы, сериалы и шоу',
    portrait_favorite_books             STRING          COMMENT 'Любимые книги и авторы',
    portrait_favorite_dishes            STRING          COMMENT 'Любимые блюда и предпочтения в еде',
    portrait_best_thing_in_life         STRING          COMMENT 'Мнение пользователя о самом хорошем в жизни',
    portrait_worst_thing_in_life        STRING          COMMENT 'Мнение пользователя о самом ужасном в жизни',
    portrait_valued_qualities_in_people STRING          COMMENT 'Качества, которые пользователь ценит в людях',
    portrait_what_can_you_forgive       STRING          COMMENT 'Что пользователь мог бы простить, а что категорически нет',
    portrait_your_strengths             STRING          COMMENT 'Заявленные достоинства характера',
    portrait_your_weaknesses            STRING          COMMENT 'Заявленные недостатки характера',
    portrait_why_job_is_interesting    STRING          COMMENT 'Чем пользователю интересна его работа',
    portrait_most_adventurous_act       STRING          COMMENT 'Самый авантюрный поступок в жизни',
    portrait_tv_opinions                STRING          COMMENT 'Мнение о телевидении и телепередачах',
    portrait_opinion_on_profanity       STRING          COMMENT 'Отношение пользователя к использованию мата',
    portrait_favorite_cities_and_countries STRING       COMMENT 'Любимые города и страны для путешествий или жизни',
    portrait_favorite_places            STRING          COMMENT 'Любимые места (парки, заведения, локации)',
    portrait_religion_importance        STRING          COMMENT 'Какое место занимает религия в жизни пользователя'
)
COMMENT 'База профилей пользователей LovePlanet, собранная стриминг-краулером через Kafka'
STORED AS PARQUET
LOCATION '/user/hive/warehouse/loveplanet_profiles'
TBLPROPERTIES (
    'parquet.compression'='SNAPPY',
    'creator'='Python Streaming Pipeline'
);
