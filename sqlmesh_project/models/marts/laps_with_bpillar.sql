MODEL (
    name marts.laps_with_bpillar,
    kind FULL,
    cron '@daily',
    grain (session_id, car, lap),
    description 'Laps table with bpillar_quartile calculated for race sessions. BPillar definition: Drivers are ranked on the fastest 50% of their laps (not including pit in/out laps, or the first lap of the race), where the lap time was within 110% of the class fastest and 105% of the driver fastest lap.'
);

WITH class_fastest AS (
    -- Find the fastest lap time per session_id + class (race sessions only)
    SELECT
        session_id,
        class,
        MIN(lap_time) AS class_fastest_lap
    FROM marts.laps
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
    FROM marts.laps
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
    FROM marts.laps l
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

SELECT
    l.series_code,
    l.series,
    l.start_date,
    l.year,
    l.event,
    l.session,
    l.session_id,
    l.session_time,
    l.clock_time,
    l.session_time_lap_number,
    l.car,
    l.class,
    l.class_normalized,
    l.class_category,
    l.driver_name,
    l.driver_id,
    l.lap,
    l.lap_time,
    l.lap_time_s1,
    l.lap_time_s2,
    l.lap_time_s3,
    l.lap_time_driver_rank,
    l.lap_time_driver_quartile,
    COALESCE(el.quartile, l.bpillar_quartile) AS bpillar_quartile,
    l.pit_time,
    l.flags,
    l.stint_start,
    l.stint_number,
    l.stint_lap,
    l.license,
    l.license_rank,
    l.driver_country,
    l.team_name,
    l.air_temp_f,
    l.track_temp_f,
    l.humidity_percent,
    l.pressure_inhg,
    l.wind_speed_mph,
    l.wind_direction_degrees,
    l.raining
FROM marts.laps l
LEFT JOIN eligible_laps el
    ON el.session_id = l.session_id
    AND el.car = l.car
    AND el.lap = l.lap
