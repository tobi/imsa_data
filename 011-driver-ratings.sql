-- Driver Ratings Reference Table
-- Loads manual/FIA driver categorization data as fallback for WEC/ELMS

-- Load reference ratings from JSON array
CREATE OR REPLACE TABLE driver_ratings_ref AS
SELECT 
    driver_id,
    license,
    year as rating_year,
    source
FROM read_json_auto('driver_ratings.json')
WHERE license IS NOT NULL;

-- Update event_driver_summary with reference ratings where missing
-- This creates a view that merges the reference data
CREATE OR REPLACE VIEW event_driver_summary_v AS
SELECT 
    eds.*,
    COALESCE(eds.license, drr.license) AS license_merged,
    COALESCE(eds.license_rank, license_rank(drr.license)) AS license_rank_merged,
    CASE WHEN eds.license IS NULL AND drr.license IS NOT NULL THEN drr.source ELSE NULL END AS license_source
FROM event_driver_summary eds
LEFT JOIN driver_ratings_ref drr ON drr.driver_id = eds.driver_id;

-- Update drivers_v to use reference ratings
DROP VIEW IF EXISTS drivers_v;
CREATE OR REPLACE VIEW drivers_v AS
WITH driver_stats AS (
    SELECT 
        driver_id,
        MODE(driver_name) AS canonical_name,
        LAST(country ORDER BY event_date) AS country,
        LAST(license_merged ORDER BY event_date) FILTER (WHERE license_merged IS NOT NULL) AS current_license,
        LAST(license_rank_merged ORDER BY event_date) FILTER (WHERE license_rank_merged IS NOT NULL) AS current_license_rank,
        COUNT(DISTINCT (series_code, year, event)) AS total_events,
        SUM(laps) AS total_laps,
        SUM(drive_time_seconds) AS total_drive_time_seconds,
        MIN(best_lap) AS career_best_lap,
        SUM(q1_laps) AS total_q1_laps,
        SUM(q2_laps) AS total_q2_laps,
        SUM(q3_laps) AS total_q3_laps,
        SUM(q4_laps) AS total_q4_laps,
        LIST(DISTINCT series_code ORDER BY series_code) AS series_list,
        LIST(DISTINCT team ORDER BY team) FILTER (WHERE team IS NOT NULL) AS teams,
        MIN(event_date) AS first_seen,
        MAX(event_date) AS last_seen,
        MIN(year) AS first_year,
        MAX(year) AS last_year
    FROM event_driver_summary_v
    GROUP BY driver_id
)
SELECT 
    driver_id,
    canonical_name,
    country,
    current_license,
    current_license_rank,
    total_events,
    total_laps,
    ROUND(total_drive_time_seconds / 3600, 2) AS total_drive_hours,
    career_best_lap,
    total_q1_laps,
    total_q2_laps,
    total_q3_laps,
    total_q4_laps,
    ROUND(100.0 * total_q1_laps / NULLIF(total_q1_laps + total_q2_laps + total_q3_laps + total_q4_laps, 0), 1) AS career_q1_pct,
    series_list,
    teams,
    first_seen,
    last_seen,
    first_year,
    last_year
FROM driver_stats
ORDER BY total_laps DESC;

-- Summary
SELECT 'Driver ratings loaded' as status, 
       (SELECT COUNT(*) FROM driver_ratings_ref) as reference_drivers,
       (SELECT COUNT(*) FROM drivers_v WHERE current_license IS NOT NULL) as drivers_with_license;
