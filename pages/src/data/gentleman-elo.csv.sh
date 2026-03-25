#!/bin/bash
# Elo ratings for gentleman drivers (Bronze + Silver in LMP2)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv <<'SQL'
WITH gentleman AS (
    SELECT DISTINCT l.driver_id
    FROM laps l
    WHERE l.class = 'LMP2' AND l.session = 'race' AND l.year >= '2025'
      AND l.license IN ('Bronze', 'Silver', 'Unknown')
      AND l.driver_id NOT IN (
          SELECT driver_id FROM laps WHERE license IN ('Platinum', 'Gold') AND class = 'LMP2'
      )
)
SELECT
    e.driver_id, e.driver_name, e.class, e.series_code, e.year,
    e.event, e.session_date,
    e.elo_before, e.elo_after, e.delta,
    e.laps, e.cumulative_laps, e.license
FROM driver_elo e
WHERE e.driver_id IN (SELECT driver_id FROM gentleman)
  AND e.class = 'LMP2'
ORDER BY e.driver_id, e.session_date;
SQL
