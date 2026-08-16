-- Driver Identity & Event Summary
-- Creates stable driver IDs with alias resolution, per-event summaries, and rolled-up driver profiles

---------------------------------------------------------------------
-- 1. DRIVER ALIAS RESOLUTION
---------------------------------------------------------------------

-- Alias resolution lives in 000-settings.sql; this is a thin alias so drivers_v
-- and laps can never disagree on a driver_id
CREATE OR REPLACE MACRO resolve_driver_id(name) AS (resolve_driver_alias(name));

---------------------------------------------------------------------
-- 2. EVENT DRIVERS (per driver per event summary)
---------------------------------------------------------------------

CREATE OR REPLACE TABLE event_driver_summary AS
WITH race_laps AS (
    SELECT
        l.*,
        -- Use the id laps already carry, not a fresh resolution of the display name
        l.driver_id AS resolved_driver_id
    FROM laps l
    WHERE session = 'race' 
       OR session LIKE 'race-hour-%'
       OR session LIKE 'race-%'
),
driver_event_stats AS (
    SELECT 
        series_code,
        series,
        year,
        event,
        resolved_driver_id AS driver_id,
        
        -- Name (most common form this event)
        MODE(driver_name) AS driver_name,
        
        -- Car & Team
        MODE(car) AS car,
        MODE(class) AS class,
        MODE(team_name) AS team,
        MODE(chassis) AS chassis,
        MODE(manufacturer) AS manufacturer,
        
        -- License (from event_drivers if available, else from laps)
        MODE(license) AS license,
        MODE(license_rank) AS license_rank,
        MODE(driver_country) AS country,
        
        -- Performance
        COUNT(*) AS laps,
        SUM(lap_time) AS drive_time_seconds,
        MIN(lap_time) AS best_lap,
        AVG(lap_time) AS avg_lap,
        STDDEV(lap_time) AS lap_stddev,
        
        -- B-Pillar quartile distribution
        SUM(CASE WHEN bpillar_quartile = 1 THEN 1 ELSE 0 END) AS q1_laps,
        SUM(CASE WHEN bpillar_quartile = 2 THEN 1 ELSE 0 END) AS q2_laps,
        SUM(CASE WHEN bpillar_quartile = 3 THEN 1 ELSE 0 END) AS q3_laps,
        SUM(CASE WHEN bpillar_quartile = 4 THEN 1 ELSE 0 END) AS q4_laps,
        
        -- Stints
        MAX(stint_number) AS stint_count,
        
        -- Timing
        MIN(start_date) AS event_date
        
    FROM race_laps
    GROUP BY series_code, series, year, event, resolved_driver_id
)
SELECT 
    series_code,
    series,
    year,
    event,
    event_date,
    driver_id,
    driver_name,
    car,
    class,
    team,
    chassis,
    manufacturer,
    license,
    license_rank,
    country,
    laps,
    ROUND(drive_time_seconds, 3) AS drive_time_seconds,
    ROUND(drive_time_seconds / 60, 2) AS drive_time_minutes,
    ROUND(best_lap, 3) AS best_lap,
    ROUND(avg_lap, 3) AS avg_lap,
    ROUND(lap_stddev, 3) AS lap_stddev,
    q1_laps,
    q2_laps,
    q3_laps,
    q4_laps,
    -- Q1 percentage (best laps)
    ROUND(100.0 * q1_laps / NULLIF(q1_laps + q2_laps + q3_laps + q4_laps, 0), 1) AS q1_pct,
    stint_count
FROM driver_event_stats
ORDER BY year, event_date, series_code, class, laps DESC;

---------------------------------------------------------------------
-- 3. DRIVERS TABLE (rolled up across all events)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW drivers_v AS
WITH driver_stats AS (
    SELECT 
        driver_id,
        
        -- Name: most recent
        LAST(driver_name ORDER BY event_date) AS canonical_name,
        LAST(country ORDER BY event_date) AS country,
        
        -- License: most recent non-null
        LAST(license ORDER BY event_date) FILTER (WHERE license IS NOT NULL) AS current_license,
        LAST(license_rank ORDER BY event_date) FILTER (WHERE license_rank IS NOT NULL) AS current_license_rank,
        
        -- Career stats
        COUNT(DISTINCT (series_code, year, event)) AS total_events,
        SUM(laps) AS total_laps,
        SUM(drive_time_seconds) AS total_drive_time_seconds,
        MIN(best_lap) AS career_best_lap,
        
        -- B-pillar totals
        SUM(q1_laps) AS total_q1_laps,
        SUM(q2_laps) AS total_q2_laps,
        SUM(q3_laps) AS total_q3_laps,
        SUM(q4_laps) AS total_q4_laps,
        
        -- Series
        LIST(DISTINCT series_code ORDER BY series_code) AS series_list,
        
        -- Teams
        LIST(DISTINCT team ORDER BY team) FILTER (WHERE team IS NOT NULL) AS teams,
        
        -- Time span
        MIN(event_date) AS first_seen,
        MAX(event_date) AS last_seen,
        MIN(year) AS first_year,
        MAX(year) AS last_year
        
    FROM event_driver_summary
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

---------------------------------------------------------------------
-- 4. LICENSE HISTORY (track changes over time)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_license_history AS
SELECT DISTINCT
    driver_id,
    year,
    series_code,
    license,
    license_rank,
    MIN(event_date) AS first_seen_date
FROM event_driver_summary
WHERE license IS NOT NULL
GROUP BY driver_id, year, series_code, license, license_rank
ORDER BY driver_id, year, series_code;

---------------------------------------------------------------------
-- 5. UPDATE LAPS TABLE WITH RESOLVED DRIVER IDs
---------------------------------------------------------------------

-- Add resolved_driver_id column if we want to denormalize
-- (Optional - can also just use resolve_driver_id() macro at query time)

-- Verify alias resolution works
-- SELECT driver_id, canonical_name, total_events, total_laps, current_license, series_list 
-- FROM drivers_v WHERE driver_id LIKE '%jaminet%' OR driver_id LIKE '%buhk%';
