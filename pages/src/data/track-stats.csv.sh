#!/bin/bash
# Data loader for track statistics
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH track_events AS (
  SELECT
    track_id,
    track_official_name,
    track_country,
    track_lat,
    track_lon,
    series_code,
    year,
    event_id,
    event_name,
    track,
    start_date,
    race_duration_minutes,
    avg_air_temp_f,
    avg_track_temp_f,
    avg_humidity_pct,
    had_rain,
    dry
  FROM events
  WHERE race_count > 0 AND track_id IS NOT NULL
),
track_laps AS (
  SELECT
    e.track_id,
    l.class_normalized,
    l.flags,
    l.lap_time,
    l.bpillar_quartile,
    l.car,
    l.driver_name,
    l.series_code,
    l.year,
    l.event
  FROM laps l
  JOIN track_events e ON l.series_code = e.series_code
    AND l.year = e.year
    AND LOWER(l.event) = LOWER(e.track)
    AND l.session IN ('race', 'qualify-race')
),
fcy_stats AS (
  SELECT
    track_id,
    COUNT(DISTINCT CONCAT(series_code, '-', year, '-', event)) as total_races,
    SUM(CASE WHEN flags = 'FCY' THEN 1 ELSE 0 END) as fcy_laps,
    COUNT(*) as total_laps
  FROM track_laps
  GROUP BY track_id
),
lap_records AS (
  SELECT
    track_id,
    class_normalized,
    MIN(lap_time) as best_lap,
    FIRST(driver_name) as record_driver,
    FIRST(car) as record_car,
    FIRST(series_code) as record_series,
    FIRST(year) as record_year
  FROM (
    SELECT
      track_id,
      class_normalized,
      lap_time,
      driver_name,
      car,
      series_code,
      year,
      ROW_NUMBER() OVER (PARTITION BY track_id, class_normalized ORDER BY lap_time ASC) as rn
    FROM track_laps
    WHERE lap_time > 30 AND bpillar_quartile IN (1, 2)
  ) ranked
  WHERE rn = 1
  GROUP BY track_id, class_normalized
),
track_summary AS (
  SELECT
    track_id,
    track_official_name,
    track_country,
    track_lat,
    track_lon,
    COUNT(*) as event_count,
    COUNT(DISTINCT series_code) as series_count,
    MIN(year::int) as first_year,
    MAX(year::int) as last_year,
    AVG(avg_air_temp_f) as avg_air_temp,
    AVG(avg_track_temp_f) as avg_track_temp,
    AVG(avg_humidity_pct) as avg_humidity,
    SUM(CASE WHEN had_rain THEN 1 ELSE 0 END) as wet_events,
    SUM(CASE WHEN dry THEN 1 ELSE 0 END) as dry_events,
    ROUND(SUM(CASE WHEN had_rain THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as rain_pct
  FROM track_events
  GROUP BY track_id, track_official_name, track_country, track_lat, track_lon
)
SELECT
  ts.track_id,
  ts.track_official_name,
  ts.track_country,
  ts.track_lat,
  ts.track_lon,
  ts.event_count,
  ts.series_count,
  ts.first_year,
  ts.last_year,
  ROUND(ts.avg_air_temp, 1) as avg_air_temp_f,
  ROUND(ts.avg_track_temp, 1) as avg_track_temp_f,
  ROUND(ts.avg_humidity, 1) as avg_humidity_pct,
  ts.wet_events,
  ts.dry_events,
  ts.rain_pct,
  COALESCE(fs.fcy_laps, 0) as fcy_laps,
  COALESCE(fs.total_laps, 0) as total_laps,
  ROUND(COALESCE(fs.fcy_laps, 0) * 100.0 / NULLIF(fs.total_laps, 0), 2) as fcy_pct
FROM track_summary ts
LEFT JOIN fcy_stats fs ON ts.track_id = fs.track_id
ORDER BY ts.event_count DESC;
"
