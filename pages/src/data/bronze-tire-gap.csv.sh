#!/bin/bash
# Bronze vs Pro teammate lap time gap by tire age
# Shows how the gap evolves as tires wear within the same car/session

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

-- Bronze driver laps with tire age
bronze_laps AS (
    SELECT session_id, car, driver_id, driver_name, event, year, series_code,
        est_tire_age, lap_time, start_date
    FROM laps
    WHERE session = 'race' AND class = 'LMP2'
      AND license IN ('Bronze', 'Unknown')
      AND driver_id IN (SELECT driver_id FROM bronze_drivers)
      AND est_tire_age IS NOT NULL
      AND flags = 'GF' AND lap_time IS NOT NULL
      AND stint_lap >= 1 AND pit_time IS NULL
      AND lap_time_driver_quartile IN (1, 2)  -- bpillar quality
),

-- Pro teammate laps with tire age (same car, same session)
pro_laps AS (
    SELECT session_id, car, est_tire_age, lap_time
    FROM laps
    WHERE session = 'race' AND class = 'LMP2'
      AND license IN ('Platinum', 'Gold')
      AND est_tire_age IS NOT NULL
      AND flags = 'GF' AND lap_time IS NOT NULL
      AND stint_lap >= 1 AND pit_time IS NULL
      AND lap_time_driver_quartile IN (1, 2)
),

-- Per driver, per session, per tire_age bucket: median pace for both
-- Bucket tire age into groups of 3 to smooth noise
bucketed AS (
    SELECT
        b.driver_id, b.driver_name, b.session_id, b.event, b.year, b.series_code,
        b.car, b.start_date,
        (b.est_tire_age / 3) * 3 AS tire_age_bucket,
        MEDIAN(b.lap_time) AS bronze_pace,
        COUNT(*) AS bronze_laps
    FROM bronze_laps b
    WHERE b.est_tire_age <= 36  -- cap at reasonable tire life
    GROUP BY b.driver_id, b.driver_name, b.session_id, b.event, b.year,
             b.series_code, b.car, b.start_date, tire_age_bucket
    HAVING COUNT(*) >= 2
),

pro_bucketed AS (
    SELECT session_id, car,
        (est_tire_age / 3) * 3 AS tire_age_bucket,
        MEDIAN(lap_time) AS pro_pace,
        COUNT(*) AS pro_laps
    FROM pro_laps
    WHERE est_tire_age <= 36
    GROUP BY session_id, car, tire_age_bucket
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
    ROUND(p.pro_pace, 3) AS pro_pace,
    ROUND(b.bronze_pace - p.pro_pace, 3) AS gap,
    ROUND((b.bronze_pace - p.pro_pace) / p.pro_pace * 100, 2) AS gap_pct,
    b.bronze_laps,
    p.pro_laps
FROM bucketed b
JOIN pro_bucketed p ON p.session_id = b.session_id AND p.car = b.car
    AND p.tire_age_bucket = b.tire_age_bucket
ORDER BY b.driver_id, b.start_date, b.tire_age_bucket;
SQL
