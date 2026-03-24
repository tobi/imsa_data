#!/bin/bash
# Gentleman driver career analysis (Bronze + Silver)
# Both driver and pro reference use mean of top 2 quartiles (Q1+Q2 = bpillar fastest 50%)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv <<'SQL'
-- Gentleman drivers: Bronze, Silver, and Unknown license (raced 2025+)
WITH gentleman_drivers AS (
    SELECT DISTINCT l.driver_id
    FROM laps l
    WHERE l.class = 'LMP2' AND l.session = 'race' AND l.year >= '2025'
      AND l.license IN ('Bronze', 'Silver', 'Unknown')
      AND l.driver_id NOT IN (
          SELECT driver_id FROM laps WHERE license IN ('Platinum', 'Gold') AND class = 'LMP2'
      )
),

-- Car reference pace: mean of Platinum/Gold drivers' top 2 quartiles (Q1+Q2)
-- across ALL sessions of the event weekend, weighted by session type
car_reference AS (
    SELECT
        l.year, l.event, l.car,
        SUM(l.lap_time * CASE l.session
            WHEN 'race' THEN 1.0
            WHEN 'qualifying' THEN 0.7
            WHEN 'warmup' THEN 0.6
            ELSE 0.5
        END) / SUM(CASE l.session
            WHEN 'race' THEN 1.0
            WHEN 'qualifying' THEN 0.7
            WHEN 'warmup' THEN 0.6
            ELSE 0.5
        END) AS ref_pace,
        MIN(l.lap_time) AS ref_best,
        COUNT(*) AS ref_laps
    FROM laps l
    WHERE l.class = 'LMP2'
      AND l.license IN ('Platinum', 'Gold')
      AND l.lap_time_driver_quartile IN (1, 2)  -- top 2 quartiles
      AND l.lap_time IS NOT NULL
      AND l.flags = 'GF'
    GROUP BY l.year, l.event, l.car
    HAVING COUNT(*) >= 5
),

-- Gentleman driver pace: mean of their top 2 quartiles (Q1+Q2) in race sessions
driver_pace AS (
    SELECT
        l.driver_id, l.driver_name, l.car, l.event, l.year,
        l.series_code, l.license,
        COUNT(*) FILTER (WHERE l.lap_time_driver_quartile IN (1, 2)
            AND l.session = 'race') AS clean_laps,
        AVG(l.lap_time) FILTER (WHERE l.lap_time_driver_quartile IN (1, 2)
            AND l.session = 'race') AS mean_pace,
        MIN(l.lap_time) FILTER (WHERE l.lap_time_driver_quartile IN (1, 2)
            AND l.session = 'race') AS best_lap,
        MIN(l.start_date) AS start_date
    FROM laps l
    WHERE l.class = 'LMP2'
      AND l.driver_id IN (SELECT driver_id FROM gentleman_drivers)
      AND l.license IN ('Bronze', 'Silver', 'Unknown')
    GROUP BY l.driver_id, l.driver_name, l.car, l.event, l.year, l.series_code, l.license
    HAVING COUNT(*) FILTER (WHERE l.lap_time_driver_quartile IN (1, 2)
        AND l.session = 'race') >= 5
),

with_event_num AS (
    SELECT
        dp.*,
        ROUND(cr.ref_pace, 3) AS ref_pace,
        ROUND(cr.ref_best, 3) AS ref_best,
        cr.ref_laps,
        ROUND(dp.mean_pace - cr.ref_pace, 3) AS gap_to_ref,
        ROUND(dp.best_lap - cr.ref_best, 3) AS gap_to_ref_best,
        ROUND((dp.mean_pace - cr.ref_pace) / cr.ref_pace * 100, 2) AS gap_pct,
        -- Gap normalized per 1km of track length (seconds per km)
        ROUND((dp.mean_pace - cr.ref_pace) / t.length_km, 3) AS gap_per_km,
        t.length_km AS track_length_km,
        ROW_NUMBER() OVER (PARTITION BY dp.driver_id ORDER BY dp.start_date) AS career_event_num,
        SUM(dp.clean_laps) OVER (PARTITION BY dp.driver_id ORDER BY dp.start_date) AS cumulative_laps,
        d.peak_license, d.license_since_year
    FROM driver_pace dp
    LEFT JOIN car_reference cr ON cr.year = dp.year AND cr.event = dp.event AND cr.car = dp.car
    LEFT JOIN drivers d ON d.driver_id = dp.driver_id
    -- Join track length via track_aliases (normalize hyphens/spaces for matching)
    LEFT JOIN track_aliases ta ON LOWER(REPLACE(dp.event, ' ', '-')) ILIKE '%' || ta.alias || '%'
    LEFT JOIN tracks t ON t.track_id = ta.track_id
)

SELECT
    driver_id, driver_name, series_code, year, event, start_date, car,
    license, peak_license, license_since_year,
    career_event_num, clean_laps, cumulative_laps,
    ROUND(mean_pace, 3) AS median_pace,
    ROUND(best_lap, 3) AS best_lap,
    ref_pace AS pro_median,
    ref_best AS pro_best,
    ref_laps AS pro_laps,
    gap_to_ref AS gap_to_pro_median,
    gap_to_ref_best AS gap_to_pro_best,
    gap_pct,
    gap_per_km,
    track_length_km
FROM with_event_num
ORDER BY driver_id, start_date;
SQL
