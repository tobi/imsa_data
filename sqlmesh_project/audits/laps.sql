-- Laps Data Quality Audits
-- Each audit returns rows that violate the quality rule (0 rows = pass)

-- Audit: Endurance races should have minimum expected duration
-- Daytona 24h, Sebring 12h, Petit Le Mans 10h, etc.
AUDIT (
    name assert_endurance_race_duration,
    dialect duckdb
);
-- Major endurance races should have data covering most of their expected duration

WITH race_durations AS (
    SELECT
        session_id, series_code, year, event, session,
        MAX(session_time) / 3600.0 AS duration_hours
    FROM @this_model
    WHERE LOWER(session) LIKE '%race%'
      AND session NOT LIKE '%qualifying%'
    GROUP BY session_id, series_code, year, event, session
),
with_expected AS (
    SELECT *,
        CASE
            -- 24h races
            WHEN event = 'Daytona' AND session = 'race' THEN 23.0
            -- 12h races
            WHEN event = 'Sebring' THEN 11.0
            -- 10h races (Petit Le Mans)
            WHEN event = 'Road Atlanta' THEN 9.0
            -- 6h races
            WHEN event IN ('Watkins Glen', 'Indianapolis') AND duration_hours > 4 THEN 5.0
            ELSE NULL  -- Don't check standard races
        END AS min_expected_hours
    FROM race_durations
)
SELECT series_code, year, event, session,
       ROUND(duration_hours, 1) AS actual_hours,
       min_expected_hours AS expected_min_hours
FROM with_expected
WHERE min_expected_hours IS NOT NULL
  AND duration_hours < min_expected_hours;


-- Audit: Lap times should be positive
AUDIT (
    name assert_positive_lap_times,
    dialect duckdb
);

SELECT session_id, car, lap, lap_time
FROM @this_model
WHERE lap_time IS NOT NULL AND lap_time <= 0;


-- Audit: Lap times should not be unreasonably short (<20 seconds)
-- Note: Long lap times are valid in endurance racing (pit stops, red flags, repairs)
AUDIT (
    name assert_reasonable_lap_times,
    dialect duckdb
);
-- Lap times under 20s are likely data errors (no circuit has <20s laps)

SELECT session_id, car, lap, lap_time, event, session
FROM @this_model
WHERE lap_time IS NOT NULL
  AND lap_time < 20;


-- Audit: Session time should be non-negative
AUDIT (
    name assert_non_negative_session_time,
    dialect duckdb
);

SELECT session_id, car, lap, session_time
FROM @this_model
WHERE session_time IS NOT NULL AND session_time < 0;


-- Audit: Lap numbers should be positive
AUDIT (
    name assert_positive_lap_numbers,
    dialect duckdb
);

SELECT session_id, car, lap
FROM @this_model
WHERE lap <= 0;


-- Audit: Cars should have sequential lap numbers (no missing laps)
-- This catches data gaps regardless of timing (red flags are fine)
AUDIT (
    name assert_no_missing_laps,
    dialect duckdb
);
-- Each car's lap sequence should be continuous (1,2,3... not 1,2,5...)

WITH lap_sequences AS (
    SELECT
        session_id, car, lap, event, session,
        LAG(lap) OVER (PARTITION BY session_id, car ORDER BY lap) AS prev_lap
    FROM @this_model
),
gaps AS (
    SELECT *,
        lap - prev_lap AS lap_gap
    FROM lap_sequences
    WHERE prev_lap IS NOT NULL
)
SELECT session_id, car, event, session,
       prev_lap AS from_lap, lap AS to_lap,
       lap_gap - 1 AS missing_laps
FROM gaps
WHERE lap_gap > 1
ORDER BY lap_gap DESC
LIMIT 50;


-- Audit: Each race should have a reasonable number of cars
AUDIT (
    name assert_minimum_car_count,
    dialect duckdb
);
-- Races should have at least 10 cars (otherwise likely data issue)

WITH race_car_counts AS (
    SELECT
        session_id, series_code, year, event, session,
        COUNT(DISTINCT car) AS car_count
    FROM @this_model
    WHERE LOWER(session) LIKE '%race%'
      AND session NOT LIKE '%qualifying%'
    GROUP BY session_id, series_code, year, event, session
)
SELECT series_code, year, event, session, car_count
FROM race_car_counts
WHERE car_count < 10;


-- Audit: Endurance race leader should have minimum expected laps
-- Daytona ~800 laps, Sebring ~350, Petit Le Mans ~400
AUDIT (
    name assert_endurance_lap_count,
    dialect duckdb
);
-- Check that the race leader completed a reasonable number of laps

WITH race_max_laps AS (
    SELECT
        session_id, series_code, year, event, session,
        MAX(lap) AS leader_laps
    FROM @this_model
    WHERE LOWER(session) LIKE '%race%'
      AND session NOT LIKE '%qualifying%'
    GROUP BY session_id, series_code, year, event, session
),
with_expected AS (
    SELECT *,
        CASE
            -- Daytona 24h: typically 750-810 laps
            WHEN event = 'Daytona' AND session = 'race' THEN 700
            -- Sebring 12h: typically 320-360 laps
            WHEN event = 'Sebring' THEN 300
            -- Petit Le Mans 10h: typically 380-450 laps
            WHEN event = 'Road Atlanta' THEN 350
            -- Watkins Glen 6h: typically 150-200 laps
            WHEN event = 'Watkins Glen' AND leader_laps > 100 THEN 130
            ELSE NULL
        END AS min_expected_laps
    FROM race_max_laps
)
SELECT series_code, year, event, session, leader_laps, min_expected_laps
FROM with_expected
WHERE min_expected_laps IS NOT NULL
  AND leader_laps < min_expected_laps;


-- Audit: Session time should increase monotonically for each car
AUDIT (
    name warn_session_time_regression,
    dialect duckdb
);
-- Session time going backwards by >5s indicates data issues
-- (small regressions <5s can occur at 24h boundary due to timestamp precision)

WITH time_sequences AS (
    SELECT
        session_id, car, lap, session_time,
        LAG(session_time) OVER (PARTITION BY session_id, car ORDER BY lap) AS prev_session_time
    FROM @this_model
    WHERE session_time IS NOT NULL
)
SELECT session_id, car, lap, session_time, prev_session_time,
       (prev_session_time - session_time) AS time_regression_seconds
FROM time_sequences
WHERE prev_session_time IS NOT NULL
  AND session_time < prev_session_time - 5  -- Allow small regressions at 24h boundary
LIMIT 50;


-- Audit: All cars should have lap 1
AUDIT (
    name assert_cars_have_lap_one,
    dialect duckdb
);
-- Every car in a session should have a first lap recorded

WITH car_min_laps AS (
    SELECT session_id, car, event, session, MIN(lap) AS first_lap
    FROM @this_model
    GROUP BY session_id, car, event, session
)
SELECT session_id, car, event, session, first_lap
FROM car_min_laps
WHERE first_lap > 1;
