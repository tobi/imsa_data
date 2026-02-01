#!/bin/bash
# Data loader for team event history
# Shows all events a team participated in with drivers and results
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH team_event_drivers AS (
    SELECT
        e.team,
        e.series_code,
        e.year,
        e.event,
        e.event_date,
        e.car,
        e.class,
        e.chassis,
        e.manufacturer,
        e.driver,
        e.license,
        e.laps,
        ev.track_id,
        ev.track_official_name as track
    FROM event_driver_summary e
    LEFT JOIN events ev
        ON e.series_code = ev.series_code
        AND e.year = ev.year
        AND e.event = ev.event_name
    WHERE e.team IS NOT NULL
      AND e.team != ''
      AND e.event NOT LIKE '%Test%'
      AND e.event NOT LIKE '%test%'
)
SELECT
    team,
    series_code,
    year,
    event,
    event_date,
    car,
    class,
    chassis,
    manufacturer,
    track_id,
    track,
    STRING_AGG(DISTINCT driver, ', ' ORDER BY driver) as drivers,
    STRING_AGG(DISTINCT license, ', ' ORDER BY license) as licenses,
    SUM(laps) as total_laps,
    COUNT(DISTINCT driver) as driver_count
FROM team_event_drivers
GROUP BY team, series_code, year, event, event_date, car, class, chassis, manufacturer, track_id, track
ORDER BY team, event_date DESC, car;
"
