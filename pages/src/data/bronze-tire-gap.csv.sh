#!/bin/bash
# Bronze vs car reference pace by tire age
# Reference = pro drivers' Q1 laps at same tire age, same car, whole event weekend

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv <<'SQL'
WITH bronze_drivers AS (
    SELECT DISTINCT l.driver_id
    FROM laps l
    WHERE l.class = 'LMP2' AND l.session = 'race' AND l.year >= '2025'
      AND l.license IN ('Bronze', 'Unknown')
      AND l.driver_id NOT IN (
          SELECT driver_id FROM laps
          WHERE license IN ('Platinum', 'Gold') AND class = 'LMP2'
      )
),

-- Bronze driver race laps with tire age (bpillar Q1+Q2)
bronze_laps AS (
    SELECT session_id, car, driver_id, driver_name, event, year, series_code,
        est_tire_age, lap_time, start_date
    FROM laps
    WHERE session = 'race' AND class = 'LMP2'
      AND license IN ('Bronze', 'Unknown')
      AND driver_id IN (SELECT driver_id FROM bronze_drivers)
      AND est_tire_age IS NOT NULL AND est_tire_age <= 36
      AND flags = 'GF' AND lap_time IS NOT NULL
      AND stint_lap >= 1 AND pit_time IS NULL
      AND lap_time_driver_quartile IN (1, 2)
),

-- Car reference: pro Q1 laps per tire_age bucket across ALL race sessions of the event
-- This uses all race sessions for the same car at the same event
pro_ref AS (
    SELECT year, event, car,
        (est_tire_age / 3) * 3 AS tire_age_bucket,
        MEDIAN(lap_time) AS ref_pace,
        COUNT(*) AS ref_laps
    FROM laps
    WHERE session = 'race' AND class = 'LMP2'
      AND license IN ('Platinum', 'Gold')
      AND est_tire_age IS NOT NULL AND est_tire_age <= 36
      AND flags = 'GF' AND lap_time IS NOT NULL
      AND stint_lap >= 1 AND pit_time IS NULL
      AND lap_time_driver_quartile = 1  -- top quartile only for reference
    GROUP BY year, event, car, tire_age_bucket
    HAVING COUNT(*) >= 2
),

-- Bucket Bronze laps and compute median
bronze_bucketed AS (
    SELECT
        driver_id, driver_name, year, event, series_code, car,
        MIN(start_date) AS start_date,
        (est_tire_age / 3) * 3 AS tire_age_bucket,
        MEDIAN(lap_time) AS bronze_pace,
        COUNT(*) AS bronze_laps
    FROM bronze_laps
    GROUP BY driver_id, driver_name, year, event, series_code, car, tire_age_bucket
    HAVING COUNT(*) >= 2
)

SELECT
    b.driver_id,
    b.driver_name,
    b.series_code,
    b.year,
    b.event,
    b.tire_age_bucket AS tire_age,
    ROUND(b.bronze_pace, 3) AS bronze_pace,
    ROUND(p.ref_pace, 3) AS pro_pace,
    ROUND(b.bronze_pace - p.ref_pace, 3) AS gap,
    ROUND((b.bronze_pace - p.ref_pace) / p.ref_pace * 100, 2) AS gap_pct,
    b.bronze_laps,
    p.ref_laps AS pro_laps
FROM bronze_bucketed b
JOIN pro_ref p ON p.year = b.year AND p.event = b.event
    AND p.car = b.car AND p.tire_age_bucket = b.tire_age_bucket
ORDER BY b.driver_id, b.start_date, b.tire_age_bucket;
SQL
