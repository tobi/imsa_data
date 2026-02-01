-- ============================================================================
-- Normalization Layer
-- ============================================================================
-- Load each series into its own raw table with normalized column names,
-- then UNION into a unified source table. This avoids issues with different
-- column names across series (e.g., IMSA_DRIVERID vs ECM_DRIVER_ID).
--
-- IMPORTANT: defined_events and ignored_sessions from 000-settings.sql are used
-- to filter data early - we only keep sessions for events we've explicitly defined.
-- ============================================================================

-- ============================================================================
-- IMSA Series Raw Results
-- ============================================================================
CREATE OR REPLACE TEMP TABLE imsa_results_raw AS
SELECT
    'imsa' AS series_code,
    regexp_extract(filename, '^data/imsa/(\d{4})/', 1) as year,
    regexp_extract(filename, '^data/imsa/\d{4}/\d\d-([^/]+)/', 1) as event_folder,
    regexp_extract(filename, '^data/imsa/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1) as session_raw,
    normalize_session(regexp_extract(filename, '^data/imsa/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) as session_normalized,
    strptime(regexp_extract(filename, '^data/imsa/\d{4}/\d\d-[^/]+/(\d+)-[^/]+-results\.csv$', 1), '%Y%m%d%H%M') as start_date,
    TRIM(CAST(number AS VARCHAR)) as car,
    TEAM as team,
    _CLASS as class,
    VEHICLE as chassis,
    filename,
    -- Normalized driver columns
    DRIVER1_FIRSTNAME AS d1_firstname, DRIVER1_SECONDNAME AS d1_secondname,
    CAST(DRIVER1_IMSA_DRIVERID AS VARCHAR) AS d1_id, DRIVER1_COUNTRY AS d1_country, DRIVER1_LICENSE AS d1_license,
    DRIVER2_FIRSTNAME AS d2_firstname, DRIVER2_SECONDNAME AS d2_secondname,
    CAST(DRIVER2_IMSA_DRIVERID AS VARCHAR) AS d2_id, DRIVER2_COUNTRY AS d2_country, DRIVER2_LICENSE AS d2_license,
    DRIVER3_FIRSTNAME AS d3_firstname, DRIVER3_SECONDNAME AS d3_secondname,
    CAST(DRIVER3_IMSA_DRIVERID AS VARCHAR) AS d3_id, DRIVER3_COUNTRY AS d3_country, DRIVER3_LICENSE AS d3_license,
    DRIVER4_FIRSTNAME AS d4_firstname, DRIVER4_SECONDNAME AS d4_secondname,
    CAST(DRIVER4_IMSA_DRIVERID AS VARCHAR) AS d4_id, DRIVER4_COUNTRY AS d4_country, DRIVER4_LICENSE AS d4_license,
    DRIVER5_FIRSTNAME AS d5_firstname, DRIVER5_SECONDNAME AS d5_secondname,
    CAST(DRIVER5_IMSA_DRIVERID AS VARCHAR) AS d5_id, DRIVER5_COUNTRY AS d5_country, DRIVER5_LICENSE AS d5_license,
    DRIVER6_FIRSTNAME AS d6_firstname, DRIVER6_SECONDNAME AS d6_secondname,
    CAST(DRIVER6_IMSA_DRIVERID AS VARCHAR) AS d6_id, DRIVER6_COUNTRY AS d6_country, DRIVER6_LICENSE AS d6_license
FROM read_csv('data/imsa/*/*/*results.csv', union_by_name=true, filename=true, null_padding=true, normalize_names=true) r
-- Only include files with valid timestamp pattern
WHERE regexp_extract(filename, '^data/imsa/\d{4}/\d\d-[^/]+/(\d{12})-[^/]+-results\.csv$', 1) != ''
-- Only include events defined in events.json
AND EXISTS (
    SELECT 1 FROM defined_events de
    WHERE de.series_code = 'imsa'
      AND de.year = regexp_extract(r.filename, '^data/imsa/(\d{4})/', 1)
      AND de.event_folder = regexp_extract(r.filename, '^data/imsa/\d{4}/\d\d-([^/]+)/', 1)
);

-- ============================================================================
-- WEC Series Raw Results
-- ============================================================================
CREATE OR REPLACE TEMP TABLE wec_results_raw AS
SELECT
    'wec' AS series_code,
    regexp_extract(filename, '^data/wec/(\d{4})/', 1) as year,
    regexp_extract(filename, '^data/wec/\d{4}/\d\d-([^/]+)/', 1) as event_folder,
    regexp_extract(filename, '^data/wec/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1) as session_raw,
    normalize_session(regexp_extract(filename, '^data/wec/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) as session_normalized,
    strptime(regexp_extract(filename, '^data/wec/\d{4}/\d\d-[^/]+/(\d+)-[^/]+-results\.csv$', 1), '%Y%m%d%H%M') as start_date,
    TRIM(CAST(number AS VARCHAR)) as car,
    TEAM as team,
    _CLASS as class,
    VEHICLE as chassis,
    filename,
    -- Normalized driver columns (WEC uses ECM_DRIVER_ID)
    DRIVER1_FIRSTNAME AS d1_firstname, DRIVER1_SECONDNAME AS d1_secondname,
    CAST(DRIVER1_ECM_DRIVER_ID AS VARCHAR) AS d1_id, DRIVER1_COUNTRY AS d1_country, DRIVER1_LICENSE AS d1_license,
    DRIVER2_FIRSTNAME AS d2_firstname, DRIVER2_SECONDNAME AS d2_secondname,
    CAST(DRIVER2_ECM_DRIVER_ID AS VARCHAR) AS d2_id, DRIVER2_COUNTRY AS d2_country, DRIVER2_LICENSE AS d2_license,
    DRIVER3_FIRSTNAME AS d3_firstname, DRIVER3_SECONDNAME AS d3_secondname,
    CAST(DRIVER3_ECM_DRIVER_ID AS VARCHAR) AS d3_id, DRIVER3_COUNTRY AS d3_country, DRIVER3_LICENSE AS d3_license,
    DRIVER4_FIRSTNAME AS d4_firstname, DRIVER4_SECONDNAME AS d4_secondname,
    CAST(DRIVER4_ECM_DRIVER_ID AS VARCHAR) AS d4_id, DRIVER4_COUNTRY AS d4_country, DRIVER4_LICENSE AS d4_license,
    DRIVER5_FIRSTNAME AS d5_firstname, DRIVER5_SECONDNAME AS d5_secondname,
    CAST(DRIVER5_ECM_DRIVER_ID AS VARCHAR) AS d5_id, DRIVER5_COUNTRY AS d5_country, DRIVER5_LICENSE AS d5_license,
    DRIVER6_FIRSTNAME AS d6_firstname, DRIVER6_SECONDNAME AS d6_secondname,
    CAST(DRIVER6_ECM_DRIVER_ID AS VARCHAR) AS d6_id, DRIVER6_COUNTRY AS d6_country, DRIVER6_LICENSE AS d6_license
FROM read_csv('data/wec/*/*/*results.csv', union_by_name=true, filename=true, null_padding=true, normalize_names=true) r
WHERE regexp_extract(filename, '^data/wec/\d{4}/\d\d-[^/]+/(\d{12})-[^/]+-results\.csv$', 1) != ''
AND EXISTS (
    SELECT 1 FROM defined_events de
    WHERE de.series_code = 'wec'
      AND de.year = regexp_extract(r.filename, '^data/wec/(\d{4})/', 1)
      AND de.event_folder = regexp_extract(r.filename, '^data/wec/\d{4}/\d\d-([^/]+)/', 1)
)
-- Filter out ignored sessions
AND NOT EXISTS (
    SELECT 1 FROM ignored_sessions i
    WHERE i.series_code = 'wec'
      AND normalize_session(regexp_extract(r.filename, '^data/wec/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) LIKE i.session_pattern || '%'
);

-- ============================================================================
-- ELMS Series Raw Results
-- ============================================================================
CREATE OR REPLACE TEMP TABLE elms_results_raw AS
SELECT
    'elms' AS series_code,
    regexp_extract(filename, '^data/elms/(\d{4})/', 1) as year,
    regexp_extract(filename, '^data/elms/\d{4}/\d\d-([^/]+)/', 1) as event_folder,
    regexp_extract(filename, '^data/elms/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1) as session_raw,
    normalize_session(regexp_extract(filename, '^data/elms/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) as session_normalized,
    strptime(regexp_extract(filename, '^data/elms/\d{4}/\d\d-[^/]+/(\d+)-[^/]+-results\.csv$', 1), '%Y%m%d%H%M') as start_date,
    TRIM(CAST(number AS VARCHAR)) as car,
    TEAM as team,
    _CLASS as class,
    VEHICLE as chassis,
    filename,
    -- Normalized driver columns (ELMS uses ECM_DRIVER_ID)
    DRIVER1_FIRSTNAME AS d1_firstname, DRIVER1_SECONDNAME AS d1_secondname,
    CAST(DRIVER1_ECM_DRIVER_ID AS VARCHAR) AS d1_id, DRIVER1_COUNTRY AS d1_country, DRIVER1_LICENSE AS d1_license,
    DRIVER2_FIRSTNAME AS d2_firstname, DRIVER2_SECONDNAME AS d2_secondname,
    CAST(DRIVER2_ECM_DRIVER_ID AS VARCHAR) AS d2_id, DRIVER2_COUNTRY AS d2_country, DRIVER2_LICENSE AS d2_license,
    DRIVER3_FIRSTNAME AS d3_firstname, DRIVER3_SECONDNAME AS d3_secondname,
    CAST(DRIVER3_ECM_DRIVER_ID AS VARCHAR) AS d3_id, DRIVER3_COUNTRY AS d3_country, DRIVER3_LICENSE AS d3_license,
    DRIVER4_FIRSTNAME AS d4_firstname, DRIVER4_SECONDNAME AS d4_secondname,
    CAST(DRIVER4_ECM_DRIVER_ID AS VARCHAR) AS d4_id, DRIVER4_COUNTRY AS d4_country, DRIVER4_LICENSE AS d4_license,
    DRIVER5_FIRSTNAME AS d5_firstname, DRIVER5_SECONDNAME AS d5_secondname,
    CAST(DRIVER5_ECM_DRIVER_ID AS VARCHAR) AS d5_id, DRIVER5_COUNTRY AS d5_country, DRIVER5_LICENSE AS d5_license,
    DRIVER6_FIRSTNAME AS d6_firstname, DRIVER6_SECONDNAME AS d6_secondname,
    CAST(DRIVER6_ECM_DRIVER_ID AS VARCHAR) AS d6_id, DRIVER6_COUNTRY AS d6_country, DRIVER6_LICENSE AS d6_license
FROM read_csv('data/elms/*/*/*results.csv', union_by_name=true, filename=true, null_padding=true, normalize_names=true) r
WHERE regexp_extract(filename, '^data/elms/\d{4}/\d\d-[^/]+/(\d{12})-[^/]+-results\.csv$', 1) != ''
AND EXISTS (
    SELECT 1 FROM defined_events de
    WHERE de.series_code = 'elms'
      AND de.year = regexp_extract(r.filename, '^data/elms/(\d{4})/', 1)
      AND de.event_folder = regexp_extract(r.filename, '^data/elms/\d{4}/\d\d-([^/]+)/', 1)
)
AND NOT EXISTS (
    SELECT 1 FROM ignored_sessions i
    WHERE i.series_code = 'elms'
      AND normalize_session(regexp_extract(r.filename, '^data/elms/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) LIKE i.session_pattern || '%'
);

-- ============================================================================
-- ALMS Series Raw Results
-- ============================================================================
CREATE OR REPLACE TEMP TABLE alms_results_raw AS
SELECT
    'alms' AS series_code,
    regexp_extract(filename, '^data/alms/(\d{4})/', 1) as year,
    regexp_extract(filename, '^data/alms/\d{4}/\d\d-([^/]+)/', 1) as event_folder,
    regexp_extract(filename, '^data/alms/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1) as session_raw,
    normalize_session(regexp_extract(filename, '^data/alms/\d{4}/\d\d-[^/]+/\d+-([^/]+)-results\.csv$', 1)) as session_normalized,
    strptime(regexp_extract(filename, '^data/alms/\d{4}/\d\d-[^/]+/(\d+)-[^/]+-results\.csv$', 1), '%Y%m%d%H%M') as start_date,
    TRIM(CAST(number AS VARCHAR)) as car,
    TEAM as team,
    _CLASS as class,
    VEHICLE as chassis,
    filename,
    -- Normalized driver columns (ALMS uses ECM_DRIVER_ID)
    DRIVER1_FIRSTNAME AS d1_firstname, DRIVER1_SECONDNAME AS d1_secondname,
    CAST(DRIVER1_ECM_DRIVER_ID AS VARCHAR) AS d1_id, DRIVER1_COUNTRY AS d1_country, DRIVER1_LICENSE AS d1_license,
    DRIVER2_FIRSTNAME AS d2_firstname, DRIVER2_SECONDNAME AS d2_secondname,
    CAST(DRIVER2_ECM_DRIVER_ID AS VARCHAR) AS d2_id, DRIVER2_COUNTRY AS d2_country, DRIVER2_LICENSE AS d2_license,
    DRIVER3_FIRSTNAME AS d3_firstname, DRIVER3_SECONDNAME AS d3_secondname,
    CAST(DRIVER3_ECM_DRIVER_ID AS VARCHAR) AS d3_id, DRIVER3_COUNTRY AS d3_country, DRIVER3_LICENSE AS d3_license,
    DRIVER4_FIRSTNAME AS d4_firstname, DRIVER4_SECONDNAME AS d4_secondname,
    CAST(DRIVER4_ECM_DRIVER_ID AS VARCHAR) AS d4_id, DRIVER4_COUNTRY AS d4_country, DRIVER4_LICENSE AS d4_license,
    DRIVER5_FIRSTNAME AS d5_firstname, DRIVER5_SECONDNAME AS d5_secondname,
    CAST(DRIVER5_ECM_DRIVER_ID AS VARCHAR) AS d5_id, DRIVER5_COUNTRY AS d5_country, DRIVER5_LICENSE AS d5_license,
    DRIVER6_FIRSTNAME AS d6_firstname, DRIVER6_SECONDNAME AS d6_secondname,
    CAST(DRIVER6_ECM_DRIVER_ID AS VARCHAR) AS d6_id, DRIVER6_COUNTRY AS d6_country, DRIVER6_LICENSE AS d6_license
FROM read_csv('data/alms/*/*/*results.csv', union_by_name=true, filename=true, null_padding=true, normalize_names=true) r
WHERE regexp_extract(filename, '^data/alms/\d{4}/\d\d-[^/]+/(\d{12})-[^/]+-results\.csv$', 1) != ''
AND EXISTS (
    SELECT 1 FROM defined_events de
    WHERE de.series_code = 'alms'
      AND de.year = regexp_extract(r.filename, '^data/alms/(\d{4})/', 1)
      AND de.event_folder = regexp_extract(r.filename, '^data/alms/\d{4}/\d\d-([^/]+)/', 1)
);

-- ============================================================================
-- Unified Results Table (normalized column names, filtered to defined events)
-- ============================================================================
CREATE OR REPLACE TEMP TABLE results_normalized AS
SELECT * FROM imsa_results_raw
UNION ALL
SELECT * FROM wec_results_raw
UNION ALL
SELECT * FROM elms_results_raw
UNION ALL
SELECT * FROM alms_results_raw;

-- Verify counts
SELECT series_code, COUNT(*) as rows, COUNT(DISTINCT event_folder) as events, COUNT(d1_firstname) as with_driver1
FROM results_normalized
GROUP BY series_code
ORDER BY series_code;
