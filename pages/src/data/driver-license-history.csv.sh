#!/bin/bash
# Data loader for driver_id license history over time
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    driver_id,
    year,
    series_code,
    license,
    license_rank,
    first_seen_date
FROM driver_license_history
ORDER BY driver_id, first_seen_date;
"
