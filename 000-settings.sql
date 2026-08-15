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
    unnest.aliases,
    unnest.length_km
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

-- Temperature handling is DETERMINISTIC and single-pass.
--
-- Source units are a per-series property (see data/series.json): IMSA reports °F,
-- WEC/ELMS/ALMS/LMC report °C. `import.rb` performs the ONE and only unit
-- conversion when it writes the CSVs, so everything on disk is already °F.
--
-- Therefore the SQL layer must NEVER convert again — doing so double-converted any
-- value that happened to fall in an ambiguous band (e.g. cold WEC rounds: a real
-- 70°F track became 158°F). This macro is a pass-through kept only so callers in
-- 030-event-weather.sql need no changes; range sanitization happens at the call
-- sites via the BETWEEN filters. avg_air/avg_track are unused and retained only
-- for signature stability.
CREATE OR REPLACE MACRO temperature(series_id, temp_value, avg_air, avg_track) AS (
    temp_value
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

-- Per-event race-name mappings (e.g. Yas Marina 2024: race-201 -> "Race 1").
-- Each event in events.json may carry an optional "races" array:
--   "races": [{"session": "race-201", "name": "Race 1"}, ...]
-- This maps a (series, year, event_folder, session_prefix) to a human race label.
-- Events with a single race omit "races" and get no label (race_label = NULL).
CREATE OR REPLACE TABLE multi_race_mappings AS
WITH ev AS (
    SELECT
        regexp_extract(filename, 'data/([^/]+)/events.json', 1) as series_code,
        unnest.year as year,
        unnest.folder as event_folder,
        unnest.races as races
    FROM read_json_auto('data/*/events.json', filename=true, union_by_name=true) j,
         UNNEST(j.events) as unnest
)
SELECT
    ev.series_code,
    ev.year,
    ev.event_folder,
    r.session as session_prefix,
    r.name as race_label
FROM ev, UNNEST(ev.races) AS t(r)
WHERE ev.races IS NOT NULL;

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
-- ============================================================================
-- DRIVER IDENTITY RESOLUTION
-- ============================================================================
-- Single source of truth for turning a raw driver name into a driver_id.
-- Curated mappings live in driver_aliases.json (per CLAUDE.md: metadata in
-- JSON, generic SQL); everything below is mechanical and driver-agnostic.
--
-- Two layers:
--   1. MECHANICAL FOLDING (no curation needed) -- accents, case, whitespace.
--   2. CURATED ALIASES from driver_aliases.json, transitively closed so that
--      a -> b -> c collapses to c and every canonical_id resolves to itself
--      (i.e. resolution is IDEMPOTENT: resolve(resolve(x)) = resolve(x)).
-- ============================================================================

-- Load curated aliases. Persistent (not TEMP) so later duckdb sessions
-- (the Elo phase) and the linters can still see them.
CREATE OR REPLACE TABLE driver_aliases AS
SELECT alias, canonical_id
FROM read_json_auto('driver_aliases.json');

-- Mechanical folding, applied to every driver name AND to the alias keys, so
-- variants merge without anyone having to curate an entry for them:
--   * diacritics -> ascii  (André LOTTERER == Andre Lotterer)
--   * hyphen     -> space  (Jean-Baptiste == Jean Baptiste)
--   * lowercase, whitespace collapsed
-- strip_accents() handles NFD-decomposable characters; the REPLACE chain
-- covers the ligature/stroke letters it cannot decompose (ø, ß, æ, œ, đ, ł).
-- The result stays ascii-lowercase, which is what driver_id has always been.
CREATE OR REPLACE MACRO driver_canonical_form(name) AS (
    NULLIF(TRIM(REGEXP_REPLACE(
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            LOWER(strip_accents(CAST(name AS VARCHAR))),
            'ø', 'o'), 'ß', 'ss'), 'æ', 'ae'), 'œ', 'oe'), 'đ', 'd'), 'ł', 'l'), '-', ' '),
        '\s+', ' ', 'g')), '')
);

-- Alias lookup key == the folded form, so an alias written with accents or
-- hyphens ('jean-éric vergne') matches a name written without them.
CREATE OR REPLACE MACRO driver_match_key(name) AS (driver_canonical_form(name));

-- Alias edges, keyed by match key and pointing at the folded canonical id.
CREATE OR REPLACE TABLE driver_alias_edges AS
SELECT DISTINCT
    driver_match_key(alias) AS match_key,
    driver_canonical_form(canonical_id) AS canonical_id
FROM driver_aliases
WHERE driver_match_key(alias) IS NOT NULL
  AND driver_canonical_form(canonical_id) IS NOT NULL;

-- Transitive closure of the alias graph. Depth is capped so a bad (cyclic)
-- alias set degrades to "pick one deterministically" instead of looping
-- forever; lint/check_drivers.rb fails the build on cycles.
CREATE OR REPLACE TABLE driver_identity_map AS
WITH RECURSIVE walked(match_key, canonical_id, depth) AS (
    SELECT match_key, canonical_id, 0 FROM driver_alias_edges
    UNION ALL
    SELECT w.match_key, e.canonical_id, w.depth + 1
    FROM walked w
    JOIN driver_alias_edges e ON e.match_key = driver_match_key(w.canonical_id)
    WHERE w.depth < 8
      AND driver_match_key(w.canonical_id) <> w.match_key
),
terminal AS (
    SELECT match_key,
           FIRST(canonical_id ORDER BY depth DESC, canonical_id ASC) AS canonical_id
    FROM walked
    GROUP BY match_key
),
all_entries AS (
    SELECT match_key, canonical_id FROM terminal
    UNION ALL
    -- Every canonical id must resolve to itself, so that resolution is
    -- idempotent and the hyphen-folded spelling of a hyphenated id maps
    -- back to it.
    SELECT DISTINCT driver_match_key(t.canonical_id), t.canonical_id
    FROM terminal t
    WHERE NOT EXISTS (
        SELECT 1 FROM terminal x WHERE x.match_key = driver_match_key(t.canonical_id)
    )
)
-- One row per match_key (deterministic), so the lookup stays a scalar subquery.
SELECT match_key, FIRST(canonical_id ORDER BY canonical_id) AS canonical_id
FROM all_entries
GROUP BY match_key;

-- Macro to canonicalize a name: first 4 chars of first name + full surname(s)
-- This naturally merges Nick/Nicholas, Alex/Alexander, Phil/Philip, etc.
-- Falls back to plain lowercased name for single-word names.
CREATE OR REPLACE MACRO fuzzy_driver_key(name) AS (
    CASE
        WHEN REGEXP_REPLACE(TRIM(name), '\s+', ' ') NOT LIKE '% %'
        THEN LOWER(REGEXP_REPLACE(TRIM(name), '\s+', ' '))
        ELSE LOWER(
            LEFT(SPLIT_PART(REGEXP_REPLACE(TRIM(name), '\s+', ' '), ' ', 1), 4)
            || ' ' ||
            ARRAY_TO_STRING(LIST_SLICE(STRING_SPLIT(REGEXP_REPLACE(TRIM(name), '\s+', ' '), ' '), 2, 100), ' ')
        )
    END
);

-- Resolve a driver name to a canonical driver_id. THE one entry point --
-- every stage of the pipeline (010, 020, 040, 090) must go through this so
-- laps, event_drivers, event_driver_summary, drivers_v and the Elo input all
-- agree on identity.
-- 1. Exact match on the folded key (accents/case/whitespace/hyphen-insensitive)
-- 2. Fuzzy key (first4 + surname) — catches Nick/Nicholas style nicknames
-- 3. Fallback: the mechanically folded name (ascii, lowercase)
CREATE OR REPLACE MACRO resolve_driver_alias(name) AS (
    COALESCE(
        (SELECT canonical_id FROM driver_identity_map
         WHERE match_key = driver_match_key(name)),
        (SELECT canonical_id FROM driver_identity_map
         WHERE match_key = fuzzy_driver_key(driver_match_key(name))
         LIMIT 1),
        driver_canonical_form(name)
    )
);

