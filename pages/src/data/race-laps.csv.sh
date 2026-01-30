#!/bin/bash
# Data loader for race lap data
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    series_code,
    year,
    event,
    session,
    start_date,
    car,
    class,
    class_normalized,
    driver,
    license,
    team_name,
    manufacturer,
    lap,
    lap_time,
    lap_time_s1,
    lap_time_s2,
    lap_time_s3,
    stint_number,
    stint_lap,
    flags,
    pit_time,
    air_temp_f,
    track_temp_f,
    raining
FROM laps
WHERE (session LIKE 'race%' OR session LIKE 'Race%')
  AND event NOT LIKE '%Test%'
  AND event NOT LIKE '%test%'
ORDER BY series_code, start_date, car, lap;
"
