#!/bin/bash
# Data loader for 25th percentile lap times by track and class
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
  event as track,
  class_std as class,
  ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY lap_time), 3) as q1_lap_time,
  ROUND(MIN(lap_time), 3) as best_lap_time,
  COUNT(*) as lap_count
FROM laps_normalized
WHERE lap_time BETWEEN 30 AND 600
  AND class_std IS NOT NULL
GROUP BY event, class_std
HAVING COUNT(*) >= 100
ORDER BY event, class_std;
"
