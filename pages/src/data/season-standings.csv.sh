#!/bin/bash
# Data loader for season driver standings (by lap count as proxy for performance)
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    series_code,
    year,
    driver,
    license,
    class_normalized as class,
    COUNT(DISTINCT event) as events,
    COUNT(*) as total_laps,
    COUNT(DISTINCT car) as cars_driven,
    STRING_AGG(DISTINCT team_name, ', ') as teams
FROM laps
WHERE session LIKE 'race%' OR session LIKE 'Race%'
GROUP BY series_code, year, driver, license, class_normalized
ORDER BY series_code, year DESC, total_laps DESC;
"
