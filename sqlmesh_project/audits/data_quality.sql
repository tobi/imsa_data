-- Data Quality Audits for IMSA Data Pipeline
-- Each audit returns rows that violate the quality rule
-- An audit passes if it returns 0 rows

-- Audit: Lap times should be positive
AUDIT (
    name assert_positive_lap_times,
    dialect duckdb
);
-- All lap times should be positive values

SELECT session_id, car, lap, lap_time
FROM @this_model
WHERE lap_time IS NOT NULL AND lap_time <= 0;

-- Audit: Session IDs should be unique within the model
AUDIT (
    name assert_unique_session_lap,
    dialect duckdb
);
-- Each lap should be unique per session and car

SELECT session_id, car, lap, COUNT(*) as cnt
FROM @this_model
GROUP BY session_id, car, lap
HAVING COUNT(*) > 1;

-- Audit: Driver names should not be empty
AUDIT (
    name assert_driver_name_not_empty,
    dialect duckdb
);
-- Driver names should not be null or empty

SELECT session_id, car, lap, driver_name
FROM @this_model
WHERE driver_name IS NULL OR TRIM(driver_name) = '';

-- Audit: Session time should be non-negative
AUDIT (
    name assert_session_time_non_negative,
    dialect duckdb
);
-- Session time should be non-negative

SELECT session_id, car, lap, session_time
FROM @this_model
WHERE session_time IS NOT NULL AND session_time < 0;

-- Audit: Lap numbers should be positive integers
AUDIT (
    name assert_positive_lap_numbers,
    dialect duckdb
);
-- Lap numbers should be positive

SELECT session_id, car, lap
FROM @this_model
WHERE lap <= 0;

-- Audit: BPillar quartile should be 1-4 when set
AUDIT (
    name assert_valid_bpillar_quartile,
    dialect duckdb
);
-- BPillar quartile should be between 1 and 4

SELECT session_id, car, lap, bpillar_quartile
FROM @this_model
WHERE bpillar_quartile IS NOT NULL
  AND (bpillar_quartile < 1 OR bpillar_quartile > 4);
