-- Create a view that joins event_laps with weather data
-- Weather data is matched based on relative time from race start using UTC timestamps
-- This file starts with '004-' to ensure it runs after all tables are created

CREATE OR REPLACE VIEW laps AS
WITH weather_with_relative_time AS (
    SELECT 
        *,
        -- Calculate relative seconds from the start of each session
        time_utc_seconds - MIN(time_utc_seconds) OVER (PARTITION BY session_id) as weather_relative_seconds
    FROM event_weather
),
lap_weather_matched AS (
    SELECT 
        el.*,
        -- Find the closest weather reading for each lap
        -- Using session time (elapsed time) to match with weather relative time
        ew.time_utc,
        ew.air_temp_f,
        ew.track_temp_f,
        ew.humidity_percent,
        ew.pressure_inhg,
        ew.wind_speed_mph,
        ew.wind_direction_degrees,
        ew.rain_flag,
        ew.weather_relative_seconds,
        
        -- Calculate time difference between lap session time and weather relative time
        ABS(EXTRACT(EPOCH FROM el.session_time) - ew.weather_relative_seconds) as time_diff_seconds,
            
        -- Rank weather readings by proximity to lap time
        ROW_NUMBER() OVER (
            PARTITION BY el.session_id, el.car, el.lap 
            ORDER BY ABS(EXTRACT(EPOCH FROM el.session_time) - ew.weather_relative_seconds)
        ) as weather_rank
        
    FROM event_laps el
    LEFT JOIN weather_with_relative_time ew 
        ON el.session_id = ew.session_id
        -- Only consider weather readings within a reasonable time window (±5 minutes)
        AND ABS(EXTRACT(EPOCH FROM el.session_time) - ew.weather_relative_seconds) <= 300
)
SELECT 
    year, event, session, session_id, lap, lap_time, driver_name, car, class,
    session_time, time, pit_time, top_speed, crossing_finish_line_in_pit, flags,
    date, stint_number,
    -- Weather data (only from the closest match)
    time_utc as weather_time_utc,
    weather_relative_seconds,
    air_temp_f,
    track_temp_f,
    humidity_percent,
    pressure_inhg,
    wind_speed_mph,
    wind_direction_degrees,
    rain_flag,
    time_diff_seconds as weather_time_diff_seconds
FROM lap_weather_matched
WHERE weather_rank = 1  -- Only keep the closest weather reading
ORDER BY session_id, car, lap; 