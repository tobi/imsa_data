-- General Data Quality Audits for IMSA Data Pipeline
-- Each audit returns rows that violate the quality rule (0 rows = pass)

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
