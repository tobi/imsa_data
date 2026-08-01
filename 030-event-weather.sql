CREATE TEMP TABLE event_weather_raw AS
    SELECT
        -- Extract series from path: data/{series}/{year}/{event}/{timestamp}-{session}-weather.csv
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 1) as series_code,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 2) as year,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 3) as event,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 5) as session,

        -- Weather measurements
        time_utc_seconds::BIGINT as time_utc_seconds,
        -- Handle multiple date formats in weather files
        COALESCE(
            TRY_STRPTIME(time_utc_str, '%m/%d/%Y %I:%M:%S %p'),
            TRY_STRPTIME(time_utc_str, '%d-%b-%y %H:%M:%S')
        ) as time_utc,
        -- Raw temperature values
        -- Sanitize/validate (CHECK-only heuristic — never used to infer units):
        -- units are already Fahrenheit on disk (import.rb converts per-series).
        -- These bounds reject physically-impossible sensor readings for a running
        -- session — e.g. a track surface stuck at the 32°F freezing-point default,
        -- or sub-freezing air — which would otherwise drag session min/avg temps.
        -- Plausible racing envelope: air 32–140°F, track 35–200°F.
        CASE WHEN air_temp BETWEEN 32 AND 140 THEN air_temp::DECIMAL(6, 2) END as air_temp_raw,
        CASE WHEN track_temp BETWEEN 35 AND 200 THEN track_temp::DECIMAL(6, 2) END as track_temp_raw,
        humidity::DECIMAL(6, 2) as humidity_percent,
        pressure::DECIMAL(6, 2) as pressure_inhg,
        wind_speed::DECIMAL(6, 2) as wind_speed_mph,
        wind_direction::INT as wind_direction_degrees,
        -- Rain encoding varies: IMSA uses -1=dry, WEC uses 0=dry, ELMS uses -999=nodata
        -- Positive values indicate rain (amount in mm or flag).
        -- -999 is a NO-DATA SENTINEL and must become NULL, never false: a broken
        -- or absent rain sensor is "unknown", not "dry". Collapsing it to false
        -- silently asserts a dry track (Road America 2026 FP2 was genuinely very
        -- wet -- LMP2 best 2:11.8 vs 1:54.2 in FP1, +17.7 s, every class equally
        -- slower -- yet the feed reported RAIN=0 with humidity railed at 96%).
        -- Downstream MUST treat NULL as unknown and fall back to pace/observation.
        CASE WHEN TRY_CAST(rain AS DECIMAL) <= -999 THEN NULL
             ELSE TRY_CAST(rain AS DECIMAL) > 0 END as raining,

        -- Date
        strptime(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 4),
            '%Y%m%d%H%M'
        ) as date,

        filename

    FROM read_csv(
        "data/*/*/*/*weather.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true,
        ignore_errors=true,
        types={
            'TIME_UTC_SECONDS': 'BIGINT',
            'TIME_UTC_STR': 'STRING',
            'AIR_TEMP': 'DECIMAL(6, 2)',
            'TRACK_TEMP': 'DECIMAL(6, 2)',
            'HUMIDITY': 'DECIMAL(6, 2)',
            'PRESSURE': 'DECIMAL(6, 2)',
            'WIND_SPEED': 'DECIMAL(6, 2)',
            'WIND_DIRECTION': 'INT',
            'RAIN': 'INT'
        }
    )
    -- Filter out files that don't match the expected timestamp pattern
    WHERE regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d{12})\-([^/]+)\-weather\.csv$', 4) != '';


CREATE OR REPLACE TABLE event_weather AS WITH
named_weather AS (
    SELECT
        series_code, year, normalize_track_name(event) as event,
        -- Raw event-folder slug + normalized session type: the stable natural key
        -- used to align weather with laps (see 040-laps.sql). `event` above is the
        -- canonical venue name kept for 071-events.sql's per-event stats.
        event as event_folder,
        get_session_type(session) as session_type,
        session, date,
        time_utc_seconds, time_utc,
        AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
            OVER (PARTITION BY filename) as avg_air_temp_raw,
        AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
            OVER (PARTITION BY filename) as avg_track_temp_raw,
        temperature_checked_air(
            series_code,
            air_temp_raw,
            AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                OVER (PARTITION BY filename),
            COALESCE(
                AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
                    OVER (PARTITION BY filename),
                AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                    OVER (PARTITION BY filename)
            )
        )::DECIMAL(6, 2) as air_temp_f,
        temperature_checked_track(
            series_code,
            track_temp_raw,
            AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                OVER (PARTITION BY filename),
            COALESCE(
                AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
                    OVER (PARTITION BY filename),
                AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                    OVER (PARTITION BY filename)
            )
        )::DECIMAL(6, 2) as track_temp_f,
        humidity_percent, pressure_inhg,
        wind_speed_mph, wind_direction_degrees, raining,
        -- One logical session per (series, year, event-folder, session-type, start day).
        -- Race-hour-* files share the same filename timestamp prefix → same `date`,
        -- so they collapse into a single race timeline. relative_seconds (computed
        -- below over this partition) then measures elapsed time from race start.
        DENSE_RANK() OVER (ORDER BY series_code, year, event_folder, session_type, date) as session_id,
    FROM event_weather_raw
    ORDER BY session_id, time_utc_seconds
),
weather_with_relative_time AS (
    SELECT
        *,
        -- Calculate relative seconds from session start for easy comparison
        (time_utc_seconds - MIN(time_utc_seconds) OVER (PARTITION BY session_id)) AS relative_seconds
    FROM named_weather
)
SELECT * FROM weather_with_relative_time
-- Deduplicate: keep one weather reading per (session_id, relative_seconds)
-- in case of duplicate weather CSV files
QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id, relative_seconds ORDER BY time_utc_seconds) = 1
ORDER BY session_id, time_utc_seconds;


-- -- Summary statistics
-- SELECT
--     COUNT(DISTINCT year) as years,
--     COUNT(DISTINCT event) as events,
--     COUNT(DISTINCT session) as sessions,
--     COUNT(*) as total_weather_readings,
--     MIN(air_temp_f) as min_air_temp_f,
--     MAX(air_temp_f) as max_air_temp_f,
--     MIN(track_temp_f) as min_track_temp_f,
--     MAX(track_temp_f) as max_track_temp_f,
--     COUNT(CASE WHEN raining THEN 1 END) as rain_readings
-- FROM event_weather;
