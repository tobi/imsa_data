#!/bin/bash
# Data loader for event directory
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    event_id,
    series_code,
    year,
    event_number,
    event_name,
    track,
    track_id,
    track_official_name,
    track_country,
    track_lat,
    track_lon,
    start_date,
    end_date,
    session_count,
    race_count,
    race_duration_minutes,
    race_type,
    avg_air_temp_f,
    avg_track_temp_f,
    avg_humidity_pct,
    had_rain,
    dry,
    race_count > 0
FROM events
WHERE race_count > 0
ORDER BY start_date DESC;
"
