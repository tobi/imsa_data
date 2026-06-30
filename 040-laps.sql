-- Create a comprehensive laps table that joins event_laps with driver data and weather data
-- This file starts with '040-' to ensure it runs after all tables are created
-- The series and series_code fields appear early for easy filtering

-- Driver alias resolution is loaded in 000-settings.sql (resolve_driver_alias macro)

CREATE OR REPLACE TABLE laps AS
SELECT
    laps.series_code,
    laps.series,
    laps.start_date,
    laps.year,
    laps.event,
    laps.race_label,
    laps.session,
    laps.session_id,
    laps.session_time,
    laps.clock_time,
    laps.session_time_lap_number,
    laps.car,
    laps.class,
    laps.driver_name,
    -- Apply alias resolution to driver_id
    resolve_driver_alias(laps.driver_name) AS driver_id,
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
    laps.license_rank,
    laps.driver_country,
    laps.team_name,
    COALESCE(laps.chassis, ERROR('Unknown chassis for car ' || laps.car || ' in ' || laps.series_code || '/' || laps.year || '/' || laps.event || '/' || laps.session)) AS chassis,
    COALESCE(laps.homologation, ERROR('Unknown homologation for chassis: ' || laps.chassis)) AS homologation,
    COALESCE(laps.manufacturer, ERROR('Unknown manufacturer for chassis: ' || laps.chassis)) AS manufacturer,
    -- Weather data from the most recent reading before or at the lap time
    ew.air_temp_f,
    ew.track_temp_f,
    ew.humidity_percent,
    ew.pressure_inhg,
    ew.wind_speed_mph,
    ew.wind_direction_degrees,
    ew.raining
FROM event_laps laps
-- Align weather by NATURAL KEY, not session_id. Each table assigns session_id via
-- an independent DENSE_RANK() over a different row population (laps keeps only
-- main-class sessions; weather keeps every file), so equal ids do NOT denote the
-- same session — matching on id silently bound e.g. Daytona's race to Spa's weather.
-- (series_code, year, event_folder, session, start_date) is the stable shared grain.
LEFT JOIN event_weather ew
    ON ew.series_code = laps.series_code
    AND ew.year = laps.year
    AND ew.event_folder = laps.event_folder
    AND ew.session_type = laps.session
    AND ew.date = laps.start_date
    AND ew.relative_seconds = (
        SELECT MAX(ew2.relative_seconds)
        FROM event_weather ew2
        WHERE ew2.series_code = laps.series_code
          AND ew2.year = laps.year
          AND ew2.event_folder = laps.event_folder
          AND ew2.session_type = laps.session
          AND ew2.date = laps.start_date
          AND ew2.relative_seconds <= laps.session_time
    )
ORDER BY laps.session_id, laps.car, laps.lap;

-- Summary statistics
SELECT
    COUNT(DISTINCT series) as series_count,
    STRING_AGG(DISTINCT series ORDER BY series) as series_list,
    COUNT(DISTINCT driver_name) as drivers,
    COUNT(DISTINCT team_name) as teams,
    COUNT(DISTINCT car) as cars,
    COUNT(DISTINCT year) as years,
    COUNT(DISTINCT event) as events,
    COUNT(DISTINCT session) as sessions,
    STRING_AGG(DISTINCT class, ', ' ORDER BY class) as lap_classes,
    STRING_AGG(DISTINCT license, ', ' ORDER BY license) as licenses,
    COUNT(*) as total_laps,
    AVG(air_temp_f)::DECIMAL(6, 2) as avg_air_temp_f,
    AVG(track_temp_f)::DECIMAL(6, 2) as avg_track_temp_f,
    AVG(humidity_percent)::DECIMAL(6, 2) as avg_humidity_percent,
    AVG(pressure_inhg)::DECIMAL(6, 2) as avg_pressure_inhg,
    AVG(wind_speed_mph)::DECIMAL(6, 2) as avg_wind_speed_mph,
    COUNT(CASE WHEN raining THEN 1 END) as rainy_laps
FROM laps;

.rows
SELECT series, year, COUNT(DISTINCT event) as races, STRING_AGG(DISTINCT event, ', ') as events FROM laps WHERE session = 'race' GROUP BY series, year ORDER by ANY_VALUE(session_id);