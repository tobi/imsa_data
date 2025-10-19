-- Calculate bpillar_quartile for race sessions only
--
-- bpillar definition: "Drivers are ranked on the fastest 50% of their laps
-- (not including pit in/out laps, or the first lap of the race), where the
-- lap time was within 110% of the class fastest, and 105% of the driver's
-- fastest lap"
--
-- The bpillar_quartile column will contain:
--   - NULL for all non-race sessions
--   - NULL for laps that don't meet the criteria
--   - 1, 2, 3, or 4 for qualifying laps (1 and 2 are the "fastest 50%")

WITH class_fastest AS (
    -- Find the fastest lap time per session_id + class (race sessions only)
    SELECT
        session_id,
        class,
        MIN(lap_time) AS class_fastest_lap
    FROM laps
    WHERE session = 'race'
        AND lap_time IS NOT NULL
    GROUP BY session_id, class
),
driver_fastest AS (
    -- Find each driver's fastest lap per session_id + class
    SELECT
        session_id,
        class,
        driver_id,
        MIN(lap_time) AS driver_fastest_lap
    FROM laps
    WHERE session = 'race'
        AND lap_time IS NOT NULL
    GROUP BY session_id, class, driver_id
),
eligible_laps AS (
    -- Identify laps that meet bpillar criteria and assign quartiles
    SELECT
        l.session_id,
        l.car,
        l.lap,
        NTILE(4) OVER (
            PARTITION BY l.session_id, l.class, l.driver_id
            ORDER BY l.lap_time ASC
        ) AS quartile
    FROM laps l
    INNER JOIN class_fastest cf
        ON cf.session_id = l.session_id
        AND cf.class = l.class
    INNER JOIN driver_fastest df
        ON df.session_id = l.session_id
        AND df.class = l.class
        AND df.driver_id = l.driver_id
    WHERE l.session = 'race'
        AND l.lap_time IS NOT NULL
        AND l.lap != 1                          -- Exclude first lap of race
        AND l.stint_lap != 0                    -- Exclude pit out laps
        AND l.pit_time > 600                    -- Exclude pit in laps (>10 min indicates no pit stop)
        AND l.lap_time <= df.driver_fastest_lap * 1.05   -- Within 105% of driver's best
        AND l.lap_time <= cf.class_fastest_lap * 1.10    -- Within 110% of class best
)
UPDATE laps
SET bpillar_quartile = eligible_laps.quartile
FROM eligible_laps
WHERE laps.session_id = eligible_laps.session_id
    AND laps.car = eligible_laps.car
    AND laps.lap = eligible_laps.lap;

-- Summary: Show how many laps are in each bpillar quartile
SELECT
    'bpillar_quartile summary' AS metric,
    COUNT(CASE WHEN bpillar_quartile = 1 THEN 1 END) AS q1_laps,
    COUNT(CASE WHEN bpillar_quartile = 2 THEN 1 END) AS q2_laps,
    COUNT(CASE WHEN bpillar_quartile = 3 THEN 1 END) AS q3_laps,
    COUNT(CASE WHEN bpillar_quartile = 4 THEN 1 END) AS q4_laps,
    COUNT(CASE WHEN bpillar_quartile IS NULL THEN 1 END) AS null_laps,
    COUNT(*) AS total_laps
FROM laps
WHERE session = 'race';
