#!/bin/bash
# Bronze LMP2 driver_name career analysis
# Computes per-event stats, gap to pro teammates, and progression over time

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv <<'SQL'
-- Current Bronze / amateur LMP2 drivers (raced in 2025+)
-- Includes 'Unknown' license: IMSA results files often omit the license grade,
-- but if a driver races LMP2 and isn't Platinum/Gold/Silver, they're effectively Bronze.
WITH bronze_drivers AS (
    SELECT DISTINCT l.driver_id
    FROM laps l
    WHERE l.class = 'LMP2' AND l.session = 'race' AND l.year >= '2025'
      AND l.license IN ('Bronze', 'Unknown')
      -- Exclude drivers who also appear as Platinum/Gold (they're pros)
      AND l.driver_id NOT IN (
          SELECT driver_id FROM laps
          WHERE license IN ('Platinum', 'Gold') AND class = 'LMP2'
      )
),

-- Per-driver_name, per-session median pace on clean green-flag laps (stint_lap >= 2)
driver_pace AS (
    SELECT
        l.session_id, l.driver_id, l.driver_name, l.car, l.event, l.year,
        l.series_code, l.class, l.license,
        COUNT(*) FILTER (WHERE l.flags = 'GF' AND l.lap_time IS NOT NULL
            AND l.stint_lap >= 2 AND l.pit_time IS NULL) AS clean_laps,
        MEDIAN(l.lap_time) FILTER (WHERE l.flags = 'GF' AND l.lap_time IS NOT NULL
            AND l.stint_lap >= 2 AND l.pit_time IS NULL) AS median_pace,
        QUANTILE_CONT(l.lap_time, 0.25) FILTER (WHERE l.flags = 'GF' AND l.lap_time IS NOT NULL
            AND l.stint_lap >= 2 AND l.pit_time IS NULL) AS p25_pace,
        MIN(l.lap_time) FILTER (WHERE l.flags = 'GF' AND l.lap_time IS NOT NULL
            AND l.stint_lap >= 2 AND l.pit_time IS NULL) AS best_lap,
        l.start_date
    FROM laps l
    WHERE l.session = 'race' AND l.class = 'LMP2'
    GROUP BY l.session_id, l.driver_id, l.driver_name, l.car, l.event, l.year,
             l.series_code, l.class, l.license, l.start_date
    HAVING COUNT(*) FILTER (WHERE l.flags = 'GF' AND l.lap_time IS NOT NULL
        AND l.stint_lap >= 2 AND l.pit_time IS NULL) >= 5
),

-- Pro teammate pace for each car+session (Platinum or Gold in same car)
pro_pace AS (
    SELECT session_id, car,
        MEDIAN(lap_time) FILTER (WHERE flags = 'GF' AND lap_time IS NOT NULL
            AND stint_lap >= 2 AND pit_time IS NULL) AS pro_median,
        MIN(lap_time) FILTER (WHERE flags = 'GF' AND lap_time IS NOT NULL
            AND stint_lap >= 2 AND pit_time IS NULL) AS pro_best,
        COUNT(*) FILTER (WHERE flags = 'GF' AND lap_time IS NOT NULL
            AND stint_lap >= 2 AND pit_time IS NULL) AS pro_laps
    FROM laps
    WHERE session = 'race' AND class = 'LMP2'
      AND license IN ('Platinum', 'Gold')
    GROUP BY session_id, car
    HAVING COUNT(*) FILTER (WHERE flags = 'GF' AND lap_time IS NOT NULL
        AND stint_lap >= 2 AND pit_time IS NULL) >= 5
),

-- Running event counter per driver_name (chronological order)
with_event_num AS (
    SELECT
        dp.*,
        pp.pro_median, pp.pro_best, pp.pro_laps,
        ROUND(dp.median_pace - pp.pro_median, 3) AS gap_to_pro_median,
        ROUND(dp.best_lap - pp.pro_best, 3) AS gap_to_pro_best,
        ROUND((dp.median_pace - pp.pro_median) / pp.pro_median * 100, 2) AS gap_pct,
        ROW_NUMBER() OVER (PARTITION BY dp.driver_id ORDER BY dp.start_date) AS career_event_num,
        SUM(dp.clean_laps) OVER (PARTITION BY dp.driver_id ORDER BY dp.start_date) AS cumulative_laps
    FROM driver_pace dp
    LEFT JOIN pro_pace pp ON pp.session_id = dp.session_id AND pp.car = dp.car
    WHERE dp.driver_id IN (SELECT driver_id FROM bronze_drivers)
      AND dp.license = 'Bronze'
)

SELECT
    driver_id,
    driver_name,
    series_code,
    year,
    event,
    start_date,
    car,
    career_event_num,
    clean_laps,
    cumulative_laps,
    ROUND(median_pace, 3) AS median_pace,
    ROUND(p25_pace, 3) AS p25_pace,
    ROUND(best_lap, 3) AS best_lap,
    ROUND(pro_median, 3) AS pro_median,
    ROUND(pro_best, 3) AS pro_best,
    pro_laps,
    gap_to_pro_median,
    gap_to_pro_best,
    gap_pct
FROM with_event_num
ORDER BY driver_id, start_date;
SQL
