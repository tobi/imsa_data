#!/bin/bash
# Data loader for driver track-by-track performance
# Aggregates driver performance per track across all events
# NOTE: Only uses relative metrics (Q1%) - never averages raw lap times across events
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH driver_track_events AS (
    SELECT
        e.driver,
        ev.track_id,
        ev.track_official_name as track,
        ev.track_country,
        e.series_code,
        e.year,
        e.event,
        e.class,
        e.laps,
        e.q1_pct,
        e.drive_time_minutes
    FROM event_driver_summary e
    JOIN events ev ON e.series_code = ev.series_code
                  AND e.year = ev.year
                  AND e.event = ev.event_name
    WHERE e.event NOT LIKE '%Test%'
      AND e.event NOT LIKE '%test%'
      AND ev.track_id IS NOT NULL
)
SELECT
    driver,
    track_id,
    track,
    track_country,
    COUNT(DISTINCT (series_code || '-' || year || '-' || event)) as events,
    SUM(laps) as total_laps,
    SUM(drive_time_minutes) as total_drive_time_minutes,
    AVG(q1_pct) as avg_q1_pct,
    MIN(year) as first_year,
    MAX(year) as last_year
FROM driver_track_events
GROUP BY driver, track_id, track, track_country
ORDER BY driver, events DESC;
"
