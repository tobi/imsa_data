#!/bin/bash
# Data loader for track event history
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
  track_id,
  series_code,
  year,
  event_id,
  event_name,
  start_date,
  race_duration_minutes,
  race_type,
  avg_air_temp_f,
  avg_track_temp_f,
  avg_humidity_pct,
  had_rain,
  dry
FROM events
WHERE is_race = true AND track_id IS NOT NULL
ORDER BY track_id, start_date DESC;
"
