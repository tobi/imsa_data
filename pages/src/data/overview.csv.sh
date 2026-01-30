#!/bin/bash
# Data loader for dashboard overview stats
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    (SELECT COUNT(DISTINCT series_code || '-' || year) FROM event_driver_summary) as total_seasons,
    (SELECT COUNT(DISTINCT event_id) FROM events WHERE event_name NOT LIKE '%Test%' AND event_name NOT LIKE '%test%') as total_events,
    (SELECT COUNT(*) FROM drivers) as total_drivers,
    (SELECT COUNT(*) FROM laps l JOIN events e ON l.series_code = e.series_code AND l.year = e.year AND l.event = e.event_name WHERE e.event_name NOT LIKE '%Test%' AND e.event_name NOT LIKE '%test%') as total_laps,
    (SELECT COUNT(DISTINCT class_normalized) FROM laps WHERE class_normalized IS NOT NULL) as total_classes,
    (SELECT MIN(year) FROM event_driver_summary) as earliest_year,
    (SELECT MAX(year) FROM event_driver_summary) as latest_year;
"
