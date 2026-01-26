-- Events Table
-- Combines event metadata from events.json manifests with computed stats from laps/weather data
-- Provides a canonical event_id that can be referenced by laps

-- First, load all events.json manifests into a raw table
-- The JSON files are arrays at root level, so read_json_auto already unnests them
CREATE TEMP TABLE events_raw AS
SELECT
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/events\.json$', 1) as series_code,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/events\.json$', 2) as year,
    event_number,
    event_name,
    event_folder
FROM read_json_auto('data/*/*/events.json', filename=true);

-- Create the events table with all metadata
CREATE OR REPLACE TABLE events AS
WITH event_sessions AS (
    -- Get first and last session dates per event
    SELECT
        series_code,
        year,
        event,
        MIN(start_date) as start_date,
        MAX(start_date) as end_date,
        COUNT(DISTINCT session_id) as session_count,
        SUM(CASE WHEN session = 'race' THEN 1 ELSE 0 END) as race_count
    FROM event_laps
    GROUP BY series_code, year, event
),
event_weather_stats AS (
    -- Compute weather statistics per event
    SELECT
        series_code,
        year,
        event,
        ROUND(AVG(air_temp_f), 1) as avg_air_temp_f,
        ROUND(MIN(air_temp_f), 1) as min_air_temp_f,
        ROUND(MAX(air_temp_f), 1) as max_air_temp_f,
        ROUND(AVG(track_temp_f), 1) as avg_track_temp_f,
        ROUND(AVG(humidity_percent), 1) as avg_humidity_pct,
        SUM(CASE WHEN raining THEN 1 ELSE 0 END) > 0 as had_rain,
        ROUND(100.0 * SUM(CASE WHEN raining THEN 1 ELSE 0 END) / COUNT(*), 1) as rain_pct
    FROM event_weather
    GROUP BY series_code, year, event
),
event_race_stats AS (
    -- Get race duration from laps data
    SELECT
        series_code,
        year,
        event,
        MAX(session_time) / 60.0 as race_duration_minutes
    FROM event_laps
    WHERE session = 'race'
    GROUP BY series_code, year, event
)
SELECT
    -- Generate event_id as series-year-track (e.g., "imsa-2025-daytona")
    er.series_code || '-' || er.year || '-' || LOWER(REPLACE(normalize_track_name(er.event_folder), ' ', '-')) as event_id,
    er.series_code,
    er.year,
    er.event_number,
    er.event_name,
    er.event_folder,
    -- Track info - use normalize_track_name which will ERROR on unknown tracks
    normalize_track_name(er.event_folder) as track,
    t.track_id,
    t.official_name as track_official_name,
    t.country as track_country,
    t.latitude as track_lat,
    t.longitude as track_lon,
    -- Dates
    CAST(es.start_date AS DATE) as start_date,
    CAST(es.end_date AS DATE) as end_date,
    es.session_count,
    es.race_count,
    -- Race duration
    CAST(ers.race_duration_minutes AS INTEGER) as race_duration_minutes,
    CASE
        WHEN ers.race_duration_minutes < 180 THEN 'Sprint'
        WHEN ers.race_duration_minutes < 360 THEN 'Endurance'
        ELSE 'Ultra-Endurance'
    END as race_type,
    -- Weather stats
    ews.avg_air_temp_f,
    ews.min_air_temp_f,
    ews.max_air_temp_f,
    ews.avg_track_temp_f,
    ews.avg_humidity_pct,
    ews.had_rain,
    ews.rain_pct,
    NOT ews.had_rain as dry
FROM events_raw er
LEFT JOIN tracks t
    ON t.short_name = normalize_track_name(er.event_folder)
LEFT JOIN event_sessions es
    ON es.series_code = er.series_code
    AND es.year = er.year
    AND es.event = normalize_track_name(er.event_folder)
LEFT JOIN event_weather_stats ews
    ON ews.series_code = er.series_code
    AND ews.year = er.year
    AND ews.event = normalize_track_name(er.event_folder)
LEFT JOIN event_race_stats ers
    ON ers.series_code = er.series_code
    AND ers.year = er.year
    AND ers.event = normalize_track_name(er.event_folder)
ORDER BY er.series_code, er.year, er.event_number;

-- Display events summary
SELECT
    series_code,
    year,
    COUNT(*) as events,
    COUNT(CASE WHEN race_count > 0 THEN 1 END) as events_with_races,
    STRING_AGG(DISTINCT race_type, ', ' ORDER BY race_type) as race_types,
    ROUND(AVG(avg_air_temp_f), 1) as avg_temp_f,
    SUM(CASE WHEN had_rain THEN 1 ELSE 0 END) as wet_events
FROM events
WHERE start_date IS NOT NULL
GROUP BY series_code, year
ORDER BY series_code, year;

.rows
SELECT
    event_id,
    event_name,
    track,
    start_date,
    race_duration_minutes,
    race_type,
    avg_air_temp_f,
    dry
FROM events
WHERE start_date IS NOT NULL
ORDER BY series_code, year, event_number;
