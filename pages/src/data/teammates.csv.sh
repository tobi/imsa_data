#!/bin/bash
# Data loader for teammate relationships
# Shows all driver pairings who shared a car in the same event
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH car_drivers AS (
    SELECT
        series_code,
        year,
        event,
        event_date,
        car,
        class,
        team,
        chassis,
        manufacturer,
        driver,
        license,
        laps,
        best_lap,
        avg_lap,
        q1_pct
    FROM event_driver_summary
),
teammate_pairs AS (
    SELECT
        a.series_code,
        a.year,
        a.event,
        a.event_date,
        a.car,
        a.class,
        a.team,
        a.chassis,
        a.manufacturer,
        a.driver as driver_a,
        a.license as license_a,
        a.laps as laps_a,
        a.best_lap as best_lap_a,
        a.avg_lap as avg_lap_a,
        a.q1_pct as q1_pct_a,
        b.driver as driver_b,
        b.license as license_b,
        b.laps as laps_b,
        b.best_lap as best_lap_b,
        b.avg_lap as avg_lap_b,
        b.q1_pct as q1_pct_b
    FROM car_drivers a
    JOIN car_drivers b
        ON a.series_code = b.series_code
        AND a.year = b.year
        AND a.event = b.event
        AND a.car = b.car
        AND a.driver < b.driver  -- avoid duplicates
)
SELECT *
FROM teammate_pairs
WHERE event NOT LIKE '%Test%'
  AND event NOT LIKE '%test%'
ORDER BY series_code, event_date, car, driver_a, driver_b;
"
