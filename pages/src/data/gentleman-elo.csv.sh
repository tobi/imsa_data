#!/bin/bash
# Elo ratings for gentleman drivers (Bronze + Silver in LMP2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb -readonly -bail "$DB_PATH" -csv -nullvalue '' <<'SQL'
WITH gentleman AS (
    SELECT DISTINCT l.driver_id
    FROM laps l
    WHERE l.class = 'LMP2' AND l.session = 'race' AND l.year >= '2025'
      AND l.license IN ('Bronze', 'Silver', 'Unknown')
      AND l.driver_id NOT IN (
          SELECT driver_id FROM laps WHERE license IN ('Platinum', 'Gold') AND class = 'LMP2'
      )
), history AS (
    SELECT *,
        LAG(elo) OVER (
            PARTITION BY driver_id, class
            ORDER BY session_date, series_code, year, event
        ) AS elo_before
    FROM driver_elo
)
SELECT
    e.driver_id, e.driver_name, e.driver_name AS driver,
    e.class, e.series_code, e.year,
    e.event, e.session_date,
    e.elo, e.elo_before, e.elo AS elo_after, e.elo - e.elo_before AS delta,
    e.laps, e.cumulative_laps, e.license,
    e.skill_mu, e.skill_sigma, e.ordinal,
    e.peer_mu, e.peer_sigma, e.peer_ordinal, e.peer_elo
FROM history e
WHERE e.driver_id IN (SELECT driver_id FROM gentleman)
  AND e.class = 'LMP2'
ORDER BY e.driver_id, e.session_date, e.series_code, e.year, e.event;
SQL
