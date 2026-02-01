-- Chassis lookup table from results CSVs
-- This handles both IMSA (DRIVER1, DRIVER2...) and ELMS/WEC (DRIVER) formats
-- since we only need car -> chassis mapping, not driver data

-- Load chassis homologation data from JSON
CREATE OR REPLACE TABLE chassis_homologation AS
SELECT
    unnest.pattern,
    unnest.homologation,
    unnest.manufacturer,
    COALESCE(unnest.canonical, unnest.pattern) AS canonical
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

CREATE OR REPLACE MACRO get_canonical_chassis(chassis_name) AS (
    COALESCE(
        (SELECT ch.canonical
         FROM chassis_homologation ch
         WHERE chassis_name ILIKE '%' || ch.pattern || '%'
         ORDER BY LENGTH(ch.pattern) DESC
         LIMIT 1),
        chassis_name
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
WHERE VEHICLE IS NOT NULL
  AND regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d{12})\-([^/]+)\-results\.csv$', 4) != '';

-- Filter to defined events and main classes
CREATE OR REPLACE TABLE chassis_lookup AS
SELECT DISTINCT
    cr.series_code,
    cr.year,
    -- Get event name from defined_events, add multi-race suffix if applicable
    de.display_name ||
    COALESCE(
        (SELECT ' ' || mrm.event_suffix FROM multi_race_mappings mrm
         WHERE mrm.series_code = cr.series_code
           AND normalize_session(cr.session) LIKE mrm.session_prefix || '%'),
        ''
    ) AS event,
    -- Normalize session type using macro
    get_session_type(normalize_session(cr.session)) AS session,
    cr.start_date,
    cr.car,
    cr.class,
    get_canonical_chassis(cr.chassis) as chassis,
    get_homologation(cr.chassis) as homologation,
    get_manufacturer(cr.chassis) as manufacturer
FROM chassis_raw cr
-- Only include events defined in events.json
INNER JOIN defined_events de
    ON de.series_code = cr.series_code
    AND de.year = cr.year
    AND de.event_folder = cr.event_raw
WHERE is_main_class(cr.series_code, cr.class);

-- Show chassis by series/class
SELECT
    series_code,
    class,
    COUNT(DISTINCT chassis) as chassis_types,
    STRING_AGG(DISTINCT chassis, ', ' ORDER BY chassis) as chassis_list
FROM chassis_lookup
GROUP BY series_code, class
ORDER BY series_code, class;
