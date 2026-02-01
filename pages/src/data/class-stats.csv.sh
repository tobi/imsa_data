#!/bin/bash
# Class performance statistics by series and year
# For overview dashboard visualizations

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    series_code,
    year,
    class,
    COUNT(DISTINCT event) as events,
    COUNT(DISTINCT car) as cars,
    COUNT(DISTINCT driver) as drivers,
    COUNT(*) as total_laps,
    ROUND(AVG(CASE WHEN bpillar_quartile IN (1,2) THEN lap_time END), 3) as avg_pace,
    ROUND(MIN(CASE WHEN bpillar_quartile = 1 THEN lap_time END), 3) as best_lap,
    ROUND(STDDEV(CASE WHEN bpillar_quartile IN (1,2) THEN lap_time END), 3) as pace_stddev
FROM laps l
WHERE session = 'race'
  AND NOT EXISTS (
    SELECT 1 FROM events e
    WHERE e.series_code = l.series_code
      AND e.year = l.year
      AND e.event_name = l.event
      AND (e.event_name LIKE '%Test%' OR e.event_name LIKE '%test%')
  )
GROUP BY series_code, year, class
ORDER BY series_code, year, class;
"
