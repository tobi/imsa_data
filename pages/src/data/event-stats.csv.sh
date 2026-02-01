#!/bin/bash
# Enhanced event statistics for overview dashboard
# Includes lap counts, class breakdown, weather, cautions

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH event_laps AS (
    SELECT
        series_code,
        year,
        event,
        COUNT(*) as total_laps,
        COUNT(DISTINCT car) as cars,
        COUNT(DISTINCT driver) as drivers,
        COUNT(DISTINCT class) as classes,
        AVG(CASE WHEN bpillar_quartile IN (1,2) THEN lap_time END) as avg_race_pace,
        MIN(CASE WHEN bpillar_quartile = 1 THEN lap_time END) as fastest_lap,
        SUM(CASE WHEN flags = 'FCY' THEN 1 ELSE 0 END) as fcy_laps,
        SUM(CASE WHEN raining THEN 1 ELSE 0 END) as wet_laps
    FROM laps
    WHERE session = 'race'
    GROUP BY series_code, year, event
),
class_counts AS (
    SELECT
        series_code, year, event,
        STRING_AGG(DISTINCT class, ', ' ORDER BY class) as class_list
    FROM laps
    WHERE session = 'race'
    GROUP BY series_code, year, event
)
SELECT
    e.event_id,
    e.series_code,
    e.year,
    e.event_name,
    e.track,
    e.track_country,
    e.start_date,
    e.race_duration_minutes,
    e.race_type,
    ROUND(e.avg_air_temp_f, 1) as avg_temp_f,
    ROUND(e.avg_track_temp_f, 1) as track_temp_f,
    e.had_rain,
    ROUND(e.rain_pct * 100, 1) as rain_pct,
    el.total_laps,
    el.cars,
    el.drivers,
    el.classes,
    ROUND(el.avg_race_pace, 3) as avg_pace,
    ROUND(el.fastest_lap, 3) as fastest_lap,
    el.fcy_laps,
    ROUND(el.fcy_laps * 100.0 / NULLIF(el.total_laps, 0), 1) as fcy_pct,
    el.wet_laps,
    cc.class_list
FROM events e
LEFT JOIN event_laps el
    ON e.series_code = el.series_code
    AND e.year = el.year
    AND e.track = el.event
LEFT JOIN class_counts cc
    ON e.series_code = cc.series_code
    AND e.year = cc.year
    AND e.track = cc.event
WHERE el.total_laps > 0
  AND e.is_race = true
ORDER BY e.start_date DESC;
"
