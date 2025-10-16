
CREATE TEMP TABLE event_drivers_raw AS
    SELECT
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as year,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as event,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4) as session,

        -- Car, team, and class
        TRIM(number) as car,
        TEAM as team,
        _CLASS as class,

        -- Date
        strptime(regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3), '%Y%m%d%H%M') as start_date,

        -- Drivers list
        list_value(
            struct_pack(
                name :=  CONCAT(DRIVER1_FIRSTNAME, ' ', DRIVER1_SECONDNAME),
                driver_id := DRIVER1_IMSA_DRIVERID,
                country := DRIVER1_COUNTRY,
                license := DRIVER1_LICENSE,
                present := DRIVER1_FIRSTNAME IS NOT NULL AND DRIVER1_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER2_FIRSTNAME, ' ', DRIVER2_SECONDNAME),
                driver_id := DRIVER2_IMSA_DRIVERID,
                country := DRIVER2_COUNTRY,
                license := DRIVER2_LICENSE,
                present := DRIVER2_FIRSTNAME IS NOT NULL AND DRIVER2_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER3_FIRSTNAME, ' ', DRIVER3_SECONDNAME),
                driver_id := DRIVER3_IMSA_DRIVERID,
                country := DRIVER3_COUNTRY,
                license := DRIVER3_LICENSE,
                present := DRIVER3_FIRSTNAME IS NOT NULL AND DRIVER3_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER4_FIRSTNAME, ' ', DRIVER4_SECONDNAME),
                driver_id := DRIVER4_IMSA_DRIVERID,
                country := DRIVER4_COUNTRY,
                license := DRIVER4_LICENSE,
                present := DRIVER4_FIRSTNAME IS NOT NULL AND DRIVER4_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER5_FIRSTNAME, ' ', DRIVER5_SECONDNAME),
                driver_id := DRIVER5_IMSA_DRIVERID,
                country := DRIVER5_COUNTRY,
                license := DRIVER5_LICENSE,
                present := DRIVER5_FIRSTNAME IS NOT NULL AND DRIVER5_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER6_FIRSTNAME, ' ', DRIVER6_SECONDNAME),
                driver_id := DRIVER6_IMSA_DRIVERID,
                country := DRIVER6_COUNTRY,
                license := DRIVER6_LICENSE,
                present := DRIVER6_FIRSTNAME IS NOT NULL AND DRIVER6_SECONDNAME IS NOT NULL
            )
        ) as drivers,

        -- File name
        filename

    FROM read_csv(
        "data/*/*/*results.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    );


CREATE OR REPLACE TABLE event_drivers AS
WITH base AS (
    SELECT
        year,
        clean_event_name(event) AS event,
        session,
        start_date,
        car,
        team,
        class,
        d.driver_id::VARCHAR AS raw_driver_id,
        REGEXP_REPLACE(TRIM(d.name), '\\s+', ' ') AS name_clean,
        d.name AS name_original,
        d.license,
        license_rank(d.license) AS license_rank,
        d.country
    FROM event_drivers_raw
    CROSS JOIN UNNEST(drivers) AS u (d)
    WHERE d.present
), normalized AS (
    SELECT
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
