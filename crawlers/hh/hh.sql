CREATE TABLE IF NOT EXISTS hh (
    -- Primary Keys
    vacancy_id BIGINT COMMENT 'Unique vacancy ID from HH.ru',
    api_vacancy_id BIGINT COMMENT 'Parent API vacancy ID that returned this vacancy',
    
    -- Core Fields
    name STRING COMMENT 'Vacancy title',
    created STRING COMMENT 'Creation timestamp (ISO 8601)',
    published STRING COMMENT 'Publication timestamp (ISO 8601)',
    capture_date STRING COMMENT 'Timestamp when data was scraped (ISO 8601)',
    
    -- Work Conditions
    schedule STRING COMMENT 'Work schedule (fullDay, shift, flexible, remote)',
    experience STRING COMMENT 'Required experience level',
    employment STRING COMMENT 'Employment type (FULL, PART, PROJECT, VOLUNTEER)',
    user_test BOOLEAN COMMENT 'Whether user test is required',
    internship BOOLEAN COMMENT 'Whether internship is offered',
    night_shifts BOOLEAN COMMENT 'Whether night shifts are required',
    accept_labor_contract BOOLEAN COMMENT 'Whether labor contract is accepted',
    
    -- Work Formats (Arrays)
    work_formats ARRAY<STRING> COMMENT 'Work formats (ON_SITE, REMOTE, HYBRID, FIELD_WORK)',
    working_hours ARRAY<STRING> COMMENT 'Working hours (HOURS_8, HOURS_12, FLEXIBLE)',
    schedule_by_days ARRAY<STRING> COMMENT 'Schedule by days (FIVE_ON_TWO_OFF, SIX_ON_ONE_OFF)',
    experimental ARRAY<STRING> COMMENT 'Experimental features enabled',
    
    -- Responses
    responses INT COMMENT 'Number of responses to this vacancy',
    responses_total INT COMMENT 'Total responses (including duplicates)',
    
    -- Company Information
    company_name STRING COMMENT 'Company name',
    company_id BIGINT COMMENT 'Company ID from HH.ru',
    company_category STRING COMMENT 'Company category (COMPANY, PERSON, AGENCY)',
    company_url STRING COMMENT 'Company website URL',
    company_acc BOOLEAN COMMENT 'Whether company is accredited IT employer',
    company_reviews STRING COMMENT 'Company rating (string representation of float)',
    company_reviews_cnt INT COMMENT 'Number of company reviews',
    
    -- Location
    address STRING COMMENT 'Full address string',
    district STRING COMMENT 'District name',
    metro STRING COMMENT 'First metro station name',
    
    -- Compensation
    salary_from INT COMMENT 'Minimum salary amount (in currency units)',
    salary_to INT COMMENT 'Maximum salary amount (in currency units)',
    salary_currency STRING COMMENT 'Currency code (RUR, USD, EUR)',
    salary_gross BOOLEAN COMMENT 'Whether salary is gross (before taxes)',
    salary_per_mode_from INT COMMENT 'Salary per mode from amount',
    salary_per_mode_to INT COMMENT 'Salary per mode to amount',
    salary_mode STRING COMMENT 'Salary mode (MONTH, HOUR, DAY, YEAR)',
    salary_frequency STRING COMMENT 'Salary payment frequency',
    
    -- Location Metadata
    area_id INT COMMENT 'Area ID from HH.ru',
    area_name STRING COMMENT 'Area name (city/region)',
    
    -- Snippets (Job Description)
    snippet_req STRING COMMENT 'Requirements snippet',
    snippet_resp STRING COMMENT 'Responsibilities snippet',
    snippet_cond STRING COMMENT 'Conditions snippet',
    snippet_skill STRING COMMENT 'Skills snippet'
)
COMMENT 'HH.ru vacancies scraped from related vacancies API'
STORED AS PARQUET;
