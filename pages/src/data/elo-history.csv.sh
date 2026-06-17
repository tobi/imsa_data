#!/bin/bash
# Data loader for Elo / skill rating history
# Outputs CSV to stdout for Observable Framework time-series visualization.
#
# Sources the precomputed driver_elo table (OpenSkill two-pool ratings from
# compute_skill.py). Columns include both the overall (license-seeded) rating
# and the within-tier peer rating, with confidence (sigma).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv <<'SQL'
SELECT
    driver_id, driver_name, class, series_code, year, event, session_date,
    elo_before, elo_after, delta, laps, cumulative_laps, license,
    skill_mu, skill_sigma, ordinal,
    peer_mu, peer_sigma, peer_ordinal
FROM driver_elo
ORDER BY driver_id, session_date;
SQL
