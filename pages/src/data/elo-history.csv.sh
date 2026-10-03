#!/bin/bash
# Data loader for Elo / skill rating history
# Outputs CSV to stdout for Observable Framework time-series visualization.
#
# Sources the precomputed driver_elo table (Plackett-Luce two-pool ratings from
# compute_skill.rb). Columns include both the overall (license-seeded) rating
# and the within-tier peer rating, with confidence (sigma).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb -readonly -bail "$DB_PATH" -csv -nullvalue '' <<'SQL'
WITH history AS (
    SELECT *,
        LAG(elo) OVER (
            PARTITION BY driver_id, class
            ORDER BY session_date, series_code, year, event
        ) AS elo_before
    FROM driver_elo
)
SELECT
    driver_id, driver_name, driver_name AS driver,
    class, series_code, year, event, session_date,
    elo, elo_before, elo AS elo_after, elo - elo_before AS delta,
    laps, cumulative_laps, license,
    skill_mu, skill_sigma, ordinal,
    peer_mu, peer_sigma, peer_ordinal, peer_elo
FROM history
ORDER BY driver_id, session_date, series_code, year, event, class;
SQL
