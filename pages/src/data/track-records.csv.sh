#!/bin/bash
# Data loader for track lap records by class
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH track_laps AS (
  SELECT
    e.track_id,
    l.class_normalized,
    l.lap_time,
    l.driver,
    l.car,
    l.series_code,
    l.year,
    l.event,
    l.bpillar_quartile
  FROM laps l
  JOIN events e ON l.series_code = e.series_code
    AND l.year = e.year
    AND LOWER(l.event) = LOWER(e.track)
    AND l.session IN ('race', 'qualify-race')
  WHERE e.is_race = true
    AND e.track_id IS NOT NULL
    AND l.lap_time > 30
    AND l.bpillar_quartile IN (1, 2)
),
ranked_laps AS (
  SELECT
    track_id,
    class_normalized,
    lap_time,
    driver,
    car,
    series_code,
    year,
    event,
    ROW_NUMBER() OVER (PARTITION BY track_id, class_normalized ORDER BY lap_time ASC) as rn
  FROM track_laps
)
SELECT
  track_id,
  class_normalized as class,
  lap_time,
  driver,
  car,
  series_code,
  year,
  event
FROM ranked_laps
WHERE rn = 1
ORDER BY track_id, class_normalized;
"
