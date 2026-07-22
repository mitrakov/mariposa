CREATE SCHEMA IF NOT EXISTS zakupki;
CREATE TABLE IF NOT EXISTS zakupki.fz223_import (
  reg_number          STRING     COMMENT 'ID закупки',
  price               DECIMAL    COMMENT 'Начальная цена',
  address             STRING     COMMENT 'Почтовый адрес',
  timezone            STRING     COMMENT 'Часовой пояс организации',
  status              STRING     COMMENT 'Статус, напр. Закупка завершена',
  publish_date        DATE       COMMENT 'Размещено',
  update_date         DATE       COMMENT 'Обновлено',
  finish_date         DATE       COMMENT 'Окончание подачи заявок',
  description         STRING     COMMENT 'Объект закупки',
  method              STRING     COMMENT 'Способ закупки, напр. Закупка у единственного поставщика',
  revision            STRING     COMMENT 'Редакция',
  notice_date         STRING     COMMENT 'Дата размещения извещения',
  revision_date       STRING     COMMENT 'Дата размещения текущей редакции извещения',
  customer            STRING     COMMENT 'Наименование организации',
  `location`          STRING     COMMENT 'Место нахождения',
  inn                 STRING     COMMENT 'ИНН',
  kpp                 STRING     COMMENT 'КПП',
  ogrn                STRING     COMMENT 'ОГРН',
  contact_person      STRING     COMMENT 'Контактное лицо',
  contact_email       STRING     COMMENT 'Контактный E-mail',
  contact_phone       STRING     COMMENT 'Контактный телефон',
  api_id              BIGINT     COMMENT 'Internal: ID в URL API запроса',
  api_capture_date    TIMESTAMP  COMMENT 'Internal: время API запроса'
)
COMMENT 'Базовая таблица с сырыми данными для zakupki.gov.ru (223-ФЗ)'
STORED AS PARQUET;
