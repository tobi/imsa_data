#!/bin/bash
# Data loader for driver_name directory
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    driver_id,
    canonical_name,
    preferred_name,
    license,
    license_rank,
    country,
    team,
    last_class,
    last_year,
    last_car,
    last_seen
FROM drivers
ORDER BY canonical_name;
"
