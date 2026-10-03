-- Inspect retained timing outliers and missing upstream coverage after a build.
SELECT series_code, year, session, COUNT(*) AS laps,
       COUNT(*) FILTER (WHERE lap_time > 600) AS long_laps,
       COUNT(*) FILTER (WHERE lap_time > 600 AND pit_time > 0) AS long_laps_with_pit_time,
       COUNT(*) FILTER (WHERE lap_time IS NULL) AS missing_lap_time,
       MAX(session_time) AS max_session_seconds
FROM laps GROUP BY series_code, year, session ORDER BY series_code, year, session;

SELECT event_id, event_name, weather_status, weather_readings, air_temp_readings
FROM events WHERE start_date IS NOT NULL AND weather_status <> 'available'
ORDER BY event_id;

SELECT series_code, year, COUNT(*) AS laps,
       COUNT(air_temp_f) AS laps_with_air_temperature,
       COUNT(raining) AS laps_with_rain_observation
FROM laps GROUP BY series_code, year ORDER BY series_code, year;
