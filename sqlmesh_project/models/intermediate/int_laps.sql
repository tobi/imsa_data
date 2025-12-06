MODEL (
    name intermediate.int_laps,
    kind FULL,
    cron '@daily',
    grain (session_id, car, lap),
    description 'Intermediate laps table joining lap timing with driver data, weather, and class normalization.'
);

-- Resolve driver names to global driver IDs using drivers
WITH driver_lookup AS (
    SELECT
        driver_id AS global_driver_id,
        display_name,
        UNNEST(name_variants) AS name_variant
    FROM marts.drivers
),

laps_with_global_driver AS (
    SELECT
        laps.*,
        dl.global_driver_id,
        dl.display_name AS driver_display_name
    FROM staging.stg_event_laps laps
    LEFT JOIN driver_lookup dl
        ON dl.name_variant = laps.driver_name
),

laps_with_weather AS (
    SELECT
        laps.series_code,
        laps.series,
        laps.start_date,
        laps.year,
        laps.event,
        laps.session,
        laps.session_id,
        laps.session_time,
        laps.clock_time,
        laps.session_time_lap_number,
        laps.car,
        laps.class,
        laps.driver_name,
        laps.driver_id AS driver_name_id,  -- Original name-based ID
        laps.global_driver_id,              -- New global ID
        COALESCE(laps.driver_display_name, laps.driver_name) AS driver_display_name,
        laps.lap,
        laps.lap_time,
        laps.lap_time_s1,
        laps.lap_time_s2,
        laps.lap_time_s3,
        laps.lap_time_driver_rank,
        laps.lap_time_driver_quartile,
        laps.bpillar_quartile,
        laps.pit_time,
        laps.flags,
        laps.stint_start,
        laps.stint_number,
        laps.stint_lap,
        laps.license,
        laps.driver_country,
        laps.team_name,
        -- Weather data from the most recent reading before or at the lap time
        ew.air_temp_f,
        ew.track_temp_f,
        ew.humidity_percent,
        ew.pressure_inhg,
        ew.wind_speed_mph,
        ew.wind_direction_degrees,
        ew.raining
    FROM laps_with_global_driver laps
    LEFT JOIN staging.stg_event_weather ew
        ON ew.session_id = laps.session_id
        AND ew.relative_seconds = (
            SELECT MAX(ew2.relative_seconds)
            FROM staging.stg_event_weather ew2
            WHERE ew2.session_id = laps.session_id
              AND ew2.relative_seconds <= laps.session_time
        )
),

laps_with_class_norm AS (
    SELECT
        lw.*,
        cm.class_normalized,
        cm.class_category
    FROM laps_with_weather lw
    LEFT JOIN staging.seed_class_mapping cm
        ON cm.series_code = lw.series_code
        AND UPPER(TRIM(cm.class_original)) = UPPER(TRIM(lw.class))
)

SELECT
    series_code,
    series,
    start_date,
    year,
    event,
    session,
    session_id,
    session_time,
    clock_time,
    session_time_lap_number,
    car,
    class,
    class_normalized,
    class_category,
    driver_name,
    driver_display_name,
    global_driver_id AS driver_id,  -- Use global driver ID
    driver_name_id,                  -- Keep name-based ID for reference
    lap,
    lap_time,
    lap_time_s1,
    lap_time_s2,
    lap_time_s3,
    lap_time_driver_rank,
    lap_time_driver_quartile,
    bpillar_quartile,
    pit_time,
    flags,
    stint_start,
    stint_number,
    stint_lap,
    license,
    driver_country,
    team_name,
    air_temp_f,
    track_temp_f,
    humidity_percent,
    pressure_inhg,
    wind_speed_mph,
    wind_direction_degrees,
    raining
FROM laps_with_class_norm
ORDER BY session_id, car, lap
