#!/bin/bash
# Data loader for driver license history over time
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    driver,
    year,
    series_code,
    license,
    license_rank,
    first_seen_date
FROM driver_license_history
ORDER BY driver, first_seen_date;
"
