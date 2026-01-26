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

CREATE OR REPLACE MACRO is_main_class(c) AS (
    c IN (SELECT class FROM main_classes)
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