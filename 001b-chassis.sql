-- Chassis lookup table from results CSVs
-- This handles both IMSA (DRIVER1, DRIVER2...) and ELMS/WEC (DRIVER) formats
-- since we only need car -> chassis mapping, not driver data

-- Load chassis homologation data from JSON
CREATE OR REPLACE TABLE chassis_homologation AS
SELECT
    unnest.pattern,
    unnest.homologation,
    unnest.manufacturer
FROM read_json_auto('chassis.json') j,
     UNNEST(j.chassis);

-- Macro to look up homologation from chassis name
CREATE OR REPLACE MACRO get_homologation(chassis_name) AS (
    COALESCE(
        (SELECT ch.homologation
         FROM chassis_homologation ch
         WHERE chassis_name ILIKE '%' || ch.pattern || '%'
         ORDER BY LENGTH(ch.pattern) DESC  -- Prefer longer/more specific matches
         LIMIT 1),
        'Unknown'
    )
);

-- Macro to look up manufacturer from chassis name
CREATE OR REPLACE MACRO get_manufacturer(chassis_name) AS (
    COALESCE(
        (SELECT ch.manufacturer
         FROM chassis_homologation ch
         WHERE chassis_name ILIKE '%' || ch.pattern || '%'
         ORDER BY LENGTH(ch.pattern) DESC
         LIMIT 1),
        'Unknown'
    )
);

CREATE TEMP TABLE chassis_raw AS
SELECT DISTINCT
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as series_code,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as year,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3) as event_raw,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 5) as session,
    strptime(
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4),
        '%Y%m%d%H%M'
    ) as start_date,
    TRIM(number) as car,
    _CLASS as class,
    VEHICLE as chassis
FROM read_csv(
    "data/*/*/*/*results.csv",
    union_by_name=true,
    filename=true,
    null_padding=true,
    normalize_names=true
)
WHERE VEHICLE IS NOT NULL;

-- Normalize track names and filter to main classes
CREATE OR REPLACE TABLE chassis_lookup AS
SELECT DISTINCT
    series_code,
    year,
    normalize_track_name(event_raw) as event,
    session,
    start_date,
    car,
    class,
    chassis,
    get_homologation(chassis) as homologation,
    get_manufacturer(chassis) as manufacturer
FROM chassis_raw
WHERE is_main_class(class);

-- Show chassis by series/class
SELECT
    series_code,
    class,
    COUNT(DISTINCT chassis) as chassis_types,
    STRING_AGG(DISTINCT chassis, ', ' ORDER BY chassis) as chassis_list
FROM chassis_lookup
GROUP BY series_code, class
ORDER BY series_code, class;
