-- Create a comprehensive laps table that joins event_laps with driver data and weather data
-- This file starts with '004-' to ensure it runs after all tables are created

CREATE OR REPLACE TABLE laps AS
SELECT 
    laps.*,
    -- Weather data from the most recent reading before or at the lap time
    ew.air_temp_f,
    ew.track_temp_f,
    ew.humidity_percent,
    ew.pressure_inhg,
    ew.wind_speed_mph,
    ew.wind_direction_degrees,
    ew.raining
FROM event_laps laps
LEFT JOIN event_weather ew ON ew.session_id = laps.session_id
    AND ew.relative_seconds = (
        SELECT MAX(ew2.relative_seconds)
        FROM event_weather ew2
        WHERE ew2.session_id = laps.session_id
          AND ew2.relative_seconds <= laps.session_time
    )
ORDER BY laps.session_id, laps.car, laps.lap;

-- Summary statistics
SELECT
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
SELECT year, COUNT(DISTINCT event) as races, STRING_AGG(DISTINCT event, ', ') as events FROM laps WHERE session = 'race' GROUP BY year ORDER by ANY_VALUE(session_id);