MODEL (
    name staging.stg_event_drivers,
    kind FULL,
    cron '@daily',
    grain (series_code, year, event, session, car, driver_id),
    description 'Staged driver data extracted from race results CSVs. Unpivots 6 driver columns into rows.'
);

WITH base_csv AS (
    SELECT
        -- Extract series from path: data/{series}/{year}/{event}/{timestamp}-{session}-results.csv
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as series_code,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as year,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3) as event_raw,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 5) as session,
        series_code || '-' || year as series,

        -- Car, team, and class
        TRIM(number) as car,
        TEAM as team,
        _CLASS as class,

        -- Date
        strptime(
            regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4),
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
        "../data/*/*/*/*results.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    )
),

unpivoted AS (
    SELECT
        series_code,
        series,
        year,
        event_raw,
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
            (DRIVER1_FIRSTNAME, DRIVER1_SECONDNAME, DRIVER1_IMSA_DRIVERID, DRIVER1_COUNTRY, DRIVER1_LICENSE) AS '1',
            (DRIVER2_FIRSTNAME, DRIVER2_SECONDNAME, DRIVER2_IMSA_DRIVERID, DRIVER2_COUNTRY, DRIVER2_LICENSE) AS '2',
            (DRIVER3_FIRSTNAME, DRIVER3_SECONDNAME, DRIVER3_IMSA_DRIVERID, DRIVER3_COUNTRY, DRIVER3_LICENSE) AS '3',
            (DRIVER4_FIRSTNAME, DRIVER4_SECONDNAME, DRIVER4_IMSA_DRIVERID, DRIVER4_COUNTRY, DRIVER4_LICENSE) AS '4',
            (DRIVER5_FIRSTNAME, DRIVER5_SECONDNAME, DRIVER5_IMSA_DRIVERID, DRIVER5_COUNTRY, DRIVER5_LICENSE) AS '5',
            (DRIVER6_FIRSTNAME, DRIVER6_SECONDNAME, DRIVER6_IMSA_DRIVERID, DRIVER6_COUNTRY, DRIVER6_LICENSE) AS '6'
        )
    )
    WHERE firstname IS NOT NULL AND secondname IS NOT NULL
),

normalized AS (
    SELECT
        series_code,
        series,
        year,
        @clean_event_name(event_raw) AS event,
        session,
        start_date,
        car,
        team,
        class,
        NULLIF(TRIM(driver_id), '') AS imsa_driver_id,
        REGEXP_REPLACE(TRIM(name), '\\s+', ' ') AS canonical_name,
        name AS name_original,
        LOWER(REGEXP_REPLACE(TRIM(name), '\\s+', ' ')) AS driver_id,
        -- Fix common data typos
        CASE WHEN license = 'Platinium' THEN 'Platinum' ELSE license END AS license,
        @license_rank(CASE WHEN license = 'Platinium' THEN 'Platinum' ELSE license END) AS license_rank,
        country
    FROM unpivoted
)

SELECT
    series_code,
    series,
    year,
    event,
    session,
    start_date,
    car,
    driver_id,
    canonical_name,
    name_original AS name,
    imsa_driver_id,
    license,
    license_rank,
    team,
    class,
    country
FROM normalized
