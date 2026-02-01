.columns
.large_number_rendering all
.bail on

.highlight_colors layout red
.highlight_colors column_type gray
.highlight_colors column_name yellow bold_underline
.highlight_colors numeric_value cyan underline
.highlight_colors temporal_value red bold
.highlight_colors string_value green bold
.highlight_colors footer gray


-- Load tracks reference data from JSON
CREATE OR REPLACE TABLE tracks AS
SELECT
    unnest.id AS track_id,
    unnest.official_name,
    unnest.short_name,
    unnest.country,
    unnest.latitude,
    unnest.longitude,
    unnest.aliases
FROM read_json_auto('tracks.json') j,
     UNNEST(j.tracks);

-- Expand aliases into a lookup table for efficient matching
CREATE OR REPLACE TABLE track_aliases AS
SELECT
    t.track_id,
    t.short_name,
    UNNEST(t.aliases) AS alias
FROM tracks t;

-- Function to normalize track names using the tracks lookup
CREATE OR REPLACE MACRO normalize_track_name(event_name) AS (
    COALESCE(
        (SELECT ta.short_name
         FROM track_aliases ta
         WHERE event_name ILIKE '%' || ta.alias || '%'
         LIMIT 1),
        ERROR('Unknown track, add to mapping in tracks.json: ' || event_name)
    )
);

-- Series metadata (temperature units, etc.)
CREATE OR REPLACE TABLE series_metadata AS
SELECT
    unnest.series_code,
    unnest.temperature_unit
FROM read_json_auto('data/series.json') j,
     UNNEST(j.series);

CREATE OR REPLACE MACRO temperature(series_id, temp_value, avg_air, avg_track) AS (
    CASE
        WHEN temp_value IS NULL THEN NULL
        ELSE (
            CASE
                WHEN (SELECT temperature_unit FROM series_metadata sm WHERE sm.series_code = series_id) = 'C'
                THEN (temp_value * 9 / 5) + 32
                WHEN (SELECT temperature_unit FROM series_metadata sm WHERE sm.series_code = series_id) = 'mixed'
                THEN CASE
                    WHEN avg_air IS NULL THEN ERROR('Temperature unit ambiguous for ' || series_id || ': air=NULL, track=' || avg_track)
                    WHEN avg_air <= 30 THEN (temp_value * 9 / 5) + 32
                    WHEN avg_air >= 50 THEN temp_value
                    WHEN (COALESCE(avg_track, avg_air) - avg_air) >= 20 THEN (temp_value * 9 / 5) + 32
                    ELSE temp_value
                END
                ELSE temp_value
            END
        )
    END
);

CREATE OR REPLACE MACRO temperature_checked_air(series_id, temp_value, avg_air, avg_track) AS (
    CASE
        WHEN temp_value IS NULL THEN NULL
        ELSE temperature(series_id, temp_value, avg_air, avg_track)
    END
);

CREATE OR REPLACE MACRO temperature_checked_track(series_id, temp_value, avg_air, avg_track) AS (
    CASE
        WHEN temp_value IS NULL THEN NULL
        ELSE temperature(series_id, temp_value, avg_air, avg_track)
    END
);

-- Main series classes - loaded from classes.json
-- Filters out support series (Porsche Cups, Ferrari Challenge, etc.)
CREATE OR REPLACE TABLE main_classes AS
SELECT
    unnest.class,
    unnest.category,
    unnest.description,
    unnest.series AS series_list
FROM read_json_auto('classes.json') j,
     UNNEST(j.classes);

CREATE OR REPLACE MACRO is_main_class(series_code, class_name) AS (
    class_name IN (
        SELECT mc.class
        FROM main_classes mc
        WHERE list_contains(mc.series_list, series_code)
    )
);

CREATE OR REPLACE MACRO normalize_license(license) AS (
    CASE
        WHEN license IS NULL THEN NULL
        WHEN UPPER(TRIM(license)) IN ('P', 'PLATINUM') THEN 'Platinum'
        WHEN UPPER(TRIM(license)) IN ('G', 'GOLD') THEN 'Gold'
        WHEN UPPER(TRIM(license)) IN ('S', 'SILVER') THEN 'Silver'
        WHEN UPPER(TRIM(license)) IN ('B', 'BRONZE') THEN 'Bronze'
        ELSE license
    END
);

CREATE OR REPLACE MACRO license_rank(license) AS (
    CASE
        WHEN UPPER(license[1:1]) = 'P' THEN 5 -- Platinum
        WHEN UPPER(license[1:1]) = 'G' THEN 4 -- Gold
        WHEN UPPER(license[1:1]) = 'S' THEN 3 -- Silver
        WHEN UPPER(license[1:1]) = 'B' THEN 2 -- Bronze
        ELSE 0
    END
);

CREATE OR REPLACE MACRO parse_time (t) AS (
    EXTRACT(EPOCH FROM(
        COALESCE(
            TRY_STRPTIME(t,             '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:'  || t,   '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:00:'|| t,  '%-H:%M:%S.%g'),
            TRY_STRPTIME('23:59:59',    '%-H:%M:%S')
        )
    )::TIME)::DECIMAL(10,3)
);

CREATE OR REPLACE MACRO format_time (t) AS (
    -- Format decimal seconds as HH:MM:SS.mmm or MM:SS.mmm
    -- Handles DOUBLE values from AVG() by separating whole and fractional parts
    CASE
        WHEN t IS NULL THEN NULL
        WHEN t > 3600 THEN
            STRFTIME('%H:%M:%S', MAKE_TIMESTAMP(CAST(FLOOR(t) * 1000000 AS BIGINT))) ||
            '.' ||
            LPAD(CAST(CAST(ROUND((t - FLOOR(t)) * 1000) AS INTEGER) AS VARCHAR), 3, '0')
        ELSE
            STRFTIME('%M:%S', MAKE_TIMESTAMP(CAST(FLOOR(t) * 1000000 AS BIGINT))) ||
            '.' ||
            LPAD(CAST(CAST(ROUND((t - FLOOR(t)) * 1000) AS INTEGER) AS VARCHAR), 3, '0')
    END
);

CREATE OR REPLACE MACRO format_gap (t) AS (
    -- Format gap in seconds with sign and 3 decimal places (e.g., +4.323, -1.300)
    CASE
        WHEN t IS NULL THEN NULL
        ELSE FORMAT('{:+.3f}', t)
    END
);

-- Load explicit event definitions from JSON files
-- Each series defines its headline events per year
CREATE OR REPLACE TABLE defined_events AS
SELECT
    regexp_extract(filename, 'data/([^/]+)/events.json', 1) as series_code,
    unnest.year as year,
    unnest.folder as event_folder,
    unnest.name as display_name
FROM read_json_auto('data/*/events.json', filename=true) j,
     UNNEST(j.events) as unnest
WHERE j.events IS NOT NULL;

-- Multi-race session mappings (e.g., race-201 -> "Race 1")
CREATE OR REPLACE TABLE multi_race_mappings AS
SELECT
    regexp_extract(filename, 'data/([^/]+)/events.json', 1) as series_code,
    unnest.session_prefix,
    unnest.event_suffix
FROM read_json_auto('data/*/events.json', filename=true) j,
     UNNEST(j.multi_race_events) as unnest
WHERE j.multi_race_events IS NOT NULL;

-- Sessions to ignore (partial data files)
CREATE OR REPLACE TABLE ignored_sessions AS
WITH json_data AS (
    SELECT
        regexp_extract(filename, 'data/([^/]+)/events.json', 1) as series_code,
        j.*
    FROM read_json_auto('data/*/events.json', filename=true) j
    WHERE j.ignore_sessions IS NOT NULL AND j.ignore_sessions.patterns IS NOT NULL
)
SELECT
    series_code,
    UNNEST(ignore_sessions.patterns) as session_pattern
FROM json_data;

-- Macro to normalize session type (strips -hour-X suffix)
CREATE OR REPLACE MACRO normalize_session(session_raw) AS (
    regexp_replace(session_raw, '-hour-[0-9]+$', '')
);

-- Macro to get session type category
CREATE OR REPLACE MACRO get_session_type(session_name) AS (
    CASE
        WHEN session_name LIKE 'race%' THEN 'race'
        WHEN session_name LIKE 'qualifying%' OR session_name LIKE 'hyperpole%' OR session_name LIKE 'r24h-qualifying%' THEN 'qualifying'
        WHEN session_name LIKE 'free%practice%' OR session_name LIKE 'practice%' OR session_name LIKE 'night%session%' OR session_name LIKE 'morning%session%' OR session_name LIKE 'afternoon%session%' THEN 'practice'
        WHEN session_name LIKE 'warm%up%' THEN 'warmup'
        WHEN session_name LIKE '%test%' OR session_name LIKE 'session-%' OR session_name LIKE 'lmp2%session' OR session_name LIKE 'lmgt3%session' OR session_name LIKE '%collective%' OR session_name LIKE 'bronze%' THEN 'test'
        ELSE session_name
    END
);