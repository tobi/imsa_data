#!/bin/bash
# Data loader for driver_name best results (wins, podiums, poles)
# Joins event_results with event_drivers to get driver_name-level position data
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
-- Get position results per driver_name per event
WITH driver_results AS (
    SELECT DISTINCT
        LOWER(ed.canonical_name) as driver_name,
        er.series_code,
        er.year,
        er.event,
        er.session,
        er.start_date,
        er.position,
        er.car,
        er.class,
        er.team,
        er.status,
        er.laps_completed,
        er.fastest_lap_time,
        COALESCE(ev.track_id, t.track_id) as track_id,
        COALESCE(ev.track_official_name, t.official_name) as track
    FROM event_results er
    JOIN event_drivers ed
        ON er.series_code = ed.series_code
        AND er.year = ed.year
        AND er.event = ed.event
        AND er.car = ed.car
    LEFT JOIN events ev
        ON er.series_code = ev.series_code
        AND er.year = ev.year
        AND er.event = ev.event_name
    LEFT JOIN tracks t
        ON list_contains(t.aliases, LOWER(er.event))
        OR LOWER(er.event) = LOWER(t.short_name)
    WHERE er.session LIKE 'race%'
      AND er.event NOT LIKE '%Test%'
      AND er.event NOT LIKE '%test%'
      AND er.position > 0
)
SELECT
    driver_name,
    series_code,
    year,
    event,
    session,
    start_date,
    position,
    car,
    class,
    team,
    status,
    laps_completed,
    fastest_lap_time,
    track_id,
    track,
    CASE WHEN position = 1 THEN 1 ELSE 0 END as is_win,
    CASE WHEN position <= 3 THEN 1 ELSE 0 END as is_podium,
    CASE WHEN position <= 5 THEN 1 ELSE 0 END as is_top5,
    CASE WHEN position <= 10 THEN 1 ELSE 0 END as is_top10
FROM driver_results
ORDER BY start_date DESC, position;
"
