#!/bin/bash
# Data loader for per-event driver statistics
# Outputs CSV to stdout for Observable Framework
# Includes bpillar percentile-based lap averages

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH driver_bpillar_stats AS (
    SELECT
        series_code,
        year,
        event,
        driver,
        car,
        AVG(CASE WHEN bpillar_quartile = 1 THEN lap_time END) as avg_q1,
        AVG(CASE WHEN bpillar_quartile IN (1, 2) THEN lap_time END) as avg_q12
    FROM laps
    WHERE session = 'race'
      AND bpillar_quartile IS NOT NULL
    GROUP BY series_code, year, event, driver, car
)
SELECT
    e.series_code,
    e.year,
    e.event,
    e.event_date,
    e.driver,
    e.car,
    e.class,
    e.team,
    e.chassis,
    e.manufacturer,
    e.license,
    e.license_rank,
    e.country,
    e.laps,
    e.drive_time_minutes,
    e.best_lap,
    e.avg_lap,
    b.avg_q1,
    b.avg_q12,
    e.lap_stddev,
    e.q1_laps,
    e.q2_laps,
    e.q3_laps,
    e.q4_laps,
    e.q1_pct,
    e.stint_count
FROM event_driver_summary e
LEFT JOIN driver_bpillar_stats b
    ON e.series_code = b.series_code
    AND e.year = b.year
    AND e.event = b.event
    AND e.driver = b.driver
    AND e.car = b.car
WHERE e.event NOT LIKE '%Test%'
  AND e.event NOT LIKE '%test%'
ORDER BY e.series_code, e.event_date, e.car, e.driver;
"
