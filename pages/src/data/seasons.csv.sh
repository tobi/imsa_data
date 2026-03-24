#!/bin/bash
# Data loader for season summaries
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    series_code,
    year,
    COUNT(DISTINCT event) as events,
    COUNT(DISTINCT driver_name) as drivers,
    SUM(laps) as total_laps,
    MIN(event_date) as season_start,
    MAX(event_date) as season_end
FROM event_driver_summary
GROUP BY series_code, year
ORDER BY series_code, year DESC;
"
