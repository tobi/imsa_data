
CREATE TEMP TABLE event_drivers_raw AS
WITH base_csv AS (
    SELECT
        -- Extract series from path (supports both 'data/series/year/...' and legacy 'data/year/...')
        COALESCE(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1),
            'imsa'
        ) as series_code,
        COALESCE(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2),
            regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1)
        ) as year,
        COALESCE(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3),
            regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2)
        ) as event,
        COALESCE(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 5),
            regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4)
        ) as session,
        series_code || '-' || year as series,

        -- Car, team, and class
        TRIM(number) as car,
        TEAM as team,
        _CLASS as class,

        -- Date
        strptime(
            COALESCE(
                regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4),
                regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3)
            ),
            '%Y%m%d%H%M'
        ) as start_date,

        filename,

        -- Driver columns with type casting done once
        DRIVER1_FIRSTNAME, DRIVER1_SECONDNAME, CAST(DRIVER1_IMSA_DRIVERID AS VARCHAR) AS DRIVER1_IMSA_DRIVERID,
        DRIVER1_COUNTRY, DRIVER1_LICENSE,
        DRIVER2_FIRSTNAME, DRIVER2_SECONDNAME, CAST(DRIVER2_IMSA_DRIVERID AS VARCHAR) AS DRIVER2_IMSA_DRIVERID,
        DRIVER2_COUNTRY, DRIVER2_LICENSE,
        DRIVER3_FIRSTNAME, DRIVER3_SECONDNAME, CAST(DRIVER3_IMSA_DRIVERID AS VARCHAR) AS DRIVER3_IMSA_DRIVERID,
        DRIVER3_COUNTRY, DRIVER3_LICENSE,
        DRIVER4_FIRSTNAME, DRIVER4_SECONDNAME, CAST(DRIVER4_IMSA_DRIVERID AS VARCHAR) AS DRIVER4_IMSA_DRIVERID,
        DRIVER4_COUNTRY, DRIVER4_LICENSE,
        DRIVER5_FIRSTNAME, DRIVER5_SECONDNAME, CAST(DRIVER5_IMSA_DRIVERID AS VARCHAR) AS DRIVER5_IMSA_DRIVERID,
        DRIVER5_COUNTRY, DRIVER5_LICENSE,
        DRIVER6_FIRSTNAME, DRIVER6_SECONDNAME, CAST(DRIVER6_IMSA_DRIVERID AS VARCHAR) AS DRIVER6_IMSA_DRIVERID,
        DRIVER6_COUNTRY, DRIVER6_LICENSE

    FROM read_csv(
        ["data/*/*/*results.csv", "data/*/*/*/*results.csv"],
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    )
)
SELECT
    series_code,
    series,
    year,
    event,
    session,
    start_date,
    car,
    team,
    class,
    filename,
    CONCAT(firstname, ' ', secondname) AS name,
    driver_id,
    country,
    license
FROM base_csv
UNPIVOT (
    (firstname, secondname, driver_id, country, license)
    FOR driver_num IN (
        (DRIVER1_FIRSTNAME, DRIVER1_SECONDNAME, DRIVER1_IMSA_DRIVERID, DRIVER1_COUNTRY, DRIVER1_LICENSE) AS 1,
        (DRIVER2_FIRSTNAME, DRIVER2_SECONDNAME, DRIVER2_IMSA_DRIVERID, DRIVER2_COUNTRY, DRIVER2_LICENSE) AS 2,
        (DRIVER3_FIRSTNAME, DRIVER3_SECONDNAME, DRIVER3_IMSA_DRIVERID, DRIVER3_COUNTRY, DRIVER3_LICENSE) AS 3,
        (DRIVER4_FIRSTNAME, DRIVER4_SECONDNAME, DRIVER4_IMSA_DRIVERID, DRIVER4_COUNTRY, DRIVER4_LICENSE) AS 4,
        (DRIVER5_FIRSTNAME, DRIVER5_SECONDNAME, DRIVER5_IMSA_DRIVERID, DRIVER5_COUNTRY, DRIVER5_LICENSE) AS 5,
        (DRIVER6_FIRSTNAME, DRIVER6_SECONDNAME, DRIVER6_IMSA_DRIVERID, DRIVER6_COUNTRY, DRIVER6_LICENSE) AS 6
    )
)
WHERE firstname IS NOT NULL AND secondname IS NOT NULL;


CREATE OR REPLACE TABLE event_drivers AS
WITH base AS (
    SELECT
        series_code,
        series,
        year,
        clean_event_name(event) AS event,
        session,
        start_date,
        car,
        team,
        class,
        driver_id AS raw_driver_id,
        REGEXP_REPLACE(TRIM(name), '\\s+', ' ') AS name_clean,
        name AS name_original,
        license,
        license_rank(license) AS license_rank,
        country
    FROM event_drivers_raw
), normalized AS (
    SELECT
        series_code,
        series,
        year,
        event,
        session,
        start_date,
        car,
        team,
        class,
        NULLIF(TRIM(raw_driver_id), '') AS provided_driver_id,
        name_clean,
        name_original,
        name_clean AS canonical_name,
        LOWER(name_clean) AS name_key,
        license,
        license_rank,
        country
    FROM base
)
SELECT
    series_code,
    series,
    year,
    event,
    session,
    start_date,
    car,
    name_key AS driver_id,  -- Use normalized name as unique ID
    canonical_name,
    name_original AS name,
    provided_driver_id AS imsa_driver_id,  -- Keep IMSA ID as additional metadata
    license,
    license_rank,
    team,
    class,
    country
FROM normalized;

-- fix some unfortunate data typos
UPDATE event_drivers SET license = 'Platinum', license_rank = license_rank(license) WHERE license = 'Platinium';



CREATE TEMP TABLE drivers_snapshot AS
WITH ranked AS (
    SELECT
        driver_id,
        canonical_name,
        name,
        imsa_driver_id,
        license,
        license_rank,
        team,
        country,
        class,
        year,
        car,
        start_date,
        ROW_NUMBER() OVER (
            PARTITION BY driver_id
            ORDER BY start_date DESC
        ) AS row_num
    FROM event_drivers
)
SELECT
    driver_id,
    canonical_name,
    name AS preferred_name,
    imsa_driver_id,
    license,
    license_rank,
    country,
    team,
    class AS last_class,
    year AS last_year,
    car AS last_car,
    start_date AS last_seen
FROM ranked
WHERE row_num = 1;

CREATE OR REPLACE TABLE drivers (
    driver_id VARCHAR PRIMARY KEY,
    canonical_name VARCHAR,
    preferred_name VARCHAR,
    imsa_driver_id VARCHAR,
    license VARCHAR,
    license_rank INTEGER,
    country VARCHAR,
    team VARCHAR,
    last_class VARCHAR,
    last_year VARCHAR,
    last_car VARCHAR,
    last_seen TIMESTAMP
);

INSERT OR REPLACE INTO drivers
SELECT
    driver_id,
    canonical_name,
    preferred_name,
    imsa_driver_id,
    license,
    CAST(license_rank AS INTEGER),
    country,
    team,
    last_class,
    last_year,
    last_car,
    last_seen
FROM drivers_snapshot;

-- SELECT COUNT(DISTINCT name) as drivers, COUNT(DISTINCT license) as licenses, COUNT(DISTINCT class) as classes, COUNT(DISTINCT team) as teams, COUNT(DISTINCT country) as countries, COUNT(DISTINCT year) as years FROM event_drivers;
