
CREATE TEMP TABLE event_drivers_raw AS
WITH base_csv AS (
    SELECT
        -- Extract series from path: data/{series}/{year}/{event}/{timestamp}-{session}-results.csv
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as series_code,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as year,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3) as event,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 5) as session,
        series_code || '-' || year as series,

        -- Car, team, class, and chassis
        TRIM(number) as car,
        TEAM as team,
        _CLASS as class,
        VEHICLE as chassis,

        -- Date
        strptime(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4),
            '%Y%m%d%H%M'
        ) as start_date,

        filename,

        -- Driver columns - use COALESCE to handle different ID column names across series
        -- Driver columns: firstname, secondname, country, license for UNPIVOT
        -- Driver IDs are handled separately (COALESCE aliases break UNPIVOT in DuckDB)
        DRIVER1_FIRSTNAME, DRIVER1_SECONDNAME, DRIVER1_COUNTRY, DRIVER1_LICENSE,
        COALESCE(CAST(DRIVER1_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER1_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER1_ID,
        DRIVER2_FIRSTNAME, DRIVER2_SECONDNAME, DRIVER2_COUNTRY, DRIVER2_LICENSE,
        COALESCE(CAST(DRIVER2_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER2_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER2_ID,
        DRIVER3_FIRSTNAME, DRIVER3_SECONDNAME, DRIVER3_COUNTRY, DRIVER3_LICENSE,
        COALESCE(CAST(DRIVER3_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER3_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER3_ID,
        DRIVER4_FIRSTNAME, DRIVER4_SECONDNAME, DRIVER4_COUNTRY, DRIVER4_LICENSE,
        COALESCE(CAST(DRIVER4_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER4_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER4_ID,
        DRIVER5_FIRSTNAME, DRIVER5_SECONDNAME, DRIVER5_COUNTRY, DRIVER5_LICENSE,
        COALESCE(CAST(DRIVER5_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER5_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER5_ID,
        DRIVER6_FIRSTNAME, DRIVER6_SECONDNAME, DRIVER6_COUNTRY, DRIVER6_LICENSE,
        COALESCE(CAST(DRIVER6_IMSA_DRIVERID AS VARCHAR), CAST(DRIVER6_ECM_DRIVER_ID AS VARCHAR)) AS DRIVER6_ID

    FROM read_csv(
        "data/*/*/*/*results.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    )
    -- Filter out files that don't match the expected timestamp pattern
    WHERE regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d{12})\-([^/]+)\-results\.csv$', 4) != ''
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
    chassis,
    filename,
    CONCAT(firstname, ' ', secondname) AS name,
    -- Look up the driver ID from the pre-computed COALESCE alias using driver_num
    CASE driver_num
        WHEN '1' THEN DRIVER1_ID WHEN '2' THEN DRIVER2_ID WHEN '3' THEN DRIVER3_ID
        WHEN '4' THEN DRIVER4_ID WHEN '5' THEN DRIVER5_ID WHEN '6' THEN DRIVER6_ID
    END AS driver_id,
    country,
    license
FROM base_csv
UNPIVOT (
    (firstname, secondname, country, license)
    FOR driver_num IN (
        (DRIVER1_FIRSTNAME, DRIVER1_SECONDNAME, DRIVER1_COUNTRY, DRIVER1_LICENSE) AS '1',
        (DRIVER2_FIRSTNAME, DRIVER2_SECONDNAME, DRIVER2_COUNTRY, DRIVER2_LICENSE) AS '2',
        (DRIVER3_FIRSTNAME, DRIVER3_SECONDNAME, DRIVER3_COUNTRY, DRIVER3_LICENSE) AS '3',
        (DRIVER4_FIRSTNAME, DRIVER4_SECONDNAME, DRIVER4_COUNTRY, DRIVER4_LICENSE) AS '4',
        (DRIVER5_FIRSTNAME, DRIVER5_SECONDNAME, DRIVER5_COUNTRY, DRIVER5_LICENSE) AS '5',
        (DRIVER6_FIRSTNAME, DRIVER6_SECONDNAME, DRIVER6_COUNTRY, DRIVER6_LICENSE) AS '6'
    )
)
WHERE firstname IS NOT NULL AND secondname IS NOT NULL;


CREATE OR REPLACE TABLE event_drivers AS
WITH base AS (
    SELECT
        edr.series_code,
        edr.series,
        edr.year,
        edr.event as event_folder,
        normalize_session(edr.session) as session_normalized,
        -- Get event name from defined_events, add multi-race suffix if applicable
        de.display_name ||
        COALESCE(
            (SELECT ' ' || mrm.event_suffix FROM multi_race_mappings mrm
             WHERE mrm.series_code = edr.series_code
               AND normalize_session(edr.session) LIKE mrm.session_prefix || '%'),
            ''
        ) AS event,
        -- Normalize session type
        get_session_type(normalize_session(edr.session)) AS session,
        edr.start_date,
        edr.car,
        edr.team,
        edr.class,
        edr.chassis,
        edr.driver_id AS raw_driver_id,
        REGEXP_REPLACE(TRIM(edr.name), '\\s+', ' ') AS name_clean,
        edr.name AS name_original,
        normalize_license(edr.license) AS license,
        license_rank(normalize_license(edr.license)) AS license_rank,
        edr.country
    FROM event_drivers_raw edr
    -- Only include events defined in events.json
    INNER JOIN defined_events de
        ON de.series_code = edr.series_code
        AND de.year = edr.year
        AND de.event_folder = edr.event
    -- Filter out ignored sessions
    WHERE NOT EXISTS (
        SELECT 1 FROM ignored_sessions i
        WHERE i.series_code = edr.series_code
          AND normalize_session(edr.session) LIKE i.session_pattern || '%'
    )
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
        chassis,
        NULLIF(TRIM(raw_driver_id), '') AS provided_driver_id,
        name_clean,
        name_original,
        name_clean AS canonical_name,
        resolve_driver_alias(name_clean) AS name_key,
        license,
        license_rank,
        country
    FROM base
)
SELECT DISTINCT
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
    chassis,
    country
FROM normalized
WHERE is_main_class(series_code, class);

-- fix some unfortunate data typos
UPDATE event_drivers SET license = 'Platinum', license_rank = license_rank(license) WHERE license = 'Platinium';



CREATE TEMP TABLE drivers_snapshot AS
WITH
-- Pick the best canonical name: prefer proper casing over ALL CAPS surnames
-- WEC/ELMS use "Firstname SURNAME" format; IMSA uses "Firstname Surname"
-- Score: proper casing > ALL CAPS, accented > ascii, recent > old
best_name AS (
    SELECT DISTINCT ON (driver_id) driver_id, canonical_name
    FROM event_drivers
    ORDER BY driver_id,
        -- Penalize ALL CAPS surnames (WEC/ELMS style: "George KURTZ")
        CASE WHEN regexp_matches(canonical_name, '[A-Z]{3}') THEN 1 ELSE 0 END,
        -- Prefer names with accented characters (François > Francois)
        CASE WHEN canonical_name ~ '[àáâãäåèéêëìíîïòóôõöùúûüýÿñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝŸÑÇ]' THEN 0 ELSE 1 END,
        -- Prefer shorter names (Nick > Nicholas) — common usage
        LENGTH(canonical_name),
        -- Tiebreak: most recent
        start_date DESC
),
-- Use best name for display, but latest entry for all other fields
ranked AS (
    SELECT
        ed.driver_id,
        bn.canonical_name,
        ed.name,
        ed.imsa_driver_id,
        ed.license,
        ed.license_rank,
        ed.team,
        ed.country,
        ed.class,
        ed.year,
        ed.car,
        ed.start_date,
        ROW_NUMBER() OVER (
            PARTITION BY ed.driver_id
            ORDER BY ed.start_date DESC
        ) AS row_num
    FROM event_drivers ed
    JOIN best_name bn ON bn.driver_id = ed.driver_id
)
SELECT
    r.driver_id,
    r.canonical_name,
    r.name AS preferred_name,
    r.imsa_driver_id,
    r.license,
    r.license_rank,
    r.country,
    r.team,
    r.class AS last_class,
    r.year AS last_year,
    r.car AS last_car,
    r.start_date AS last_seen,
    -- Peak license ever achieved
    peak.peak_license,
    peak.peak_license_rank,
    -- Year current license was first seen
    cur_year.license_since_year
FROM ranked r
LEFT JOIN (
    SELECT driver_id,
        FIRST(license ORDER BY license_rank DESC) AS peak_license,
        MAX(license_rank) AS peak_license_rank
    FROM event_drivers
    WHERE license IS NOT NULL AND license != 'Unknown'
    GROUP BY driver_id
) peak ON peak.driver_id = r.driver_id
LEFT JOIN (
    SELECT driver_id, MIN(year) AS license_since_year
    FROM event_drivers
    WHERE license IS NOT NULL AND license != 'Unknown'
    GROUP BY driver_id, license
    HAVING license = (
        SELECT ed2.license FROM event_drivers ed2
        WHERE ed2.driver_id = event_drivers.driver_id
          AND ed2.license IS NOT NULL AND ed2.license != 'Unknown'
        ORDER BY ed2.start_date DESC LIMIT 1
    )
) cur_year ON cur_year.driver_id = r.driver_id
WHERE r.row_num = 1;

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
    last_seen TIMESTAMP,
    peak_license VARCHAR,
    peak_license_rank INTEGER,
    license_since_year VARCHAR
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
    last_seen,
    peak_license,
    CAST(peak_license_rank AS INTEGER),
    license_since_year
FROM drivers_snapshot;

-- SELECT COUNT(DISTINCT name) as drivers, COUNT(DISTINCT license) as licenses, COUNT(DISTINCT class) as classes, COUNT(DISTINCT team) as teams, COUNT(DISTINCT country) as countries, COUNT(DISTINCT year) as years FROM event_drivers;
