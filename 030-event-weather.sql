-- Parse decimal dots and decimal commas without discarding whole CSV rows.
CREATE OR REPLACE MACRO weather_number(value) AS (
    TRY_CAST(REPLACE(TRIM(value), ',', '.') AS DOUBLE)
);

-- Persist the parsed source observations for coverage/provenance checks before
-- duplicate timestamps are collapsed in event_weather. Unknown units stay raw.
CREATE OR REPLACE TABLE event_weather_observations AS
SELECT
    regexp_extract(filename, '^data/([^/]+)/', 1) AS series_code,
    regexp_extract(filename, '^data/[^/]+/(\d{4})/', 1) AS year,
    regexp_extract(filename, '^data/[^/]+/\d{4}/\d\d-([^/]+)/', 1) AS event,
    regexp_extract(filename, '/\d{12}-([^/]+)-weather\.csv$', 1) AS session,
    TRY_CAST(time_utc_seconds AS BIGINT) AS time_utc_seconds,
    to_timestamp(TRY_CAST(time_utc_seconds AS BIGINT))::TIMESTAMP AS time_utc,
    CASE WHEN weather_number(air_temp) BETWEEN 32 AND 140
         THEN weather_number(air_temp)::DECIMAL(6,2) END AS air_temp_raw,
    CASE WHEN weather_number(track_temp) BETWEEN 35 AND 200
         THEN weather_number(track_temp)::DECIMAL(6,2) END AS track_temp_raw,
    CASE WHEN weather_number(humidity) BETWEEN 0 AND 100
         THEN weather_number(humidity)::DECIMAL(6,2) END AS humidity_percent,
    weather_number(pressure) AS pressure_raw,
    pressure_unit,
    CASE upper(trim(pressure_unit))
      WHEN 'INHG' THEN weather_number(pressure)
      WHEN 'MBAR' THEN weather_number(pressure) / 33.8638866667
      WHEN 'HPA' THEN weather_number(pressure) / 33.8638866667
    END::DECIMAL(6,2) AS pressure_inhg,
    weather_number(wind_speed) AS wind_speed_raw,
    wind_speed_unit,
    CASE upper(trim(wind_speed_unit))
      WHEN 'MPH' THEN weather_number(wind_speed)
      WHEN 'KPH' THEN weather_number(wind_speed) / 1.609344
      WHEN 'KM/H' THEN weather_number(wind_speed) / 1.609344
      WHEN 'M/S' THEN weather_number(wind_speed) * 2.2369362921
    END::DECIMAL(6,2) AS wind_speed_mph,
    CASE WHEN weather_number(wind_direction) BETWEEN 0 AND 360
         THEN weather_number(wind_direction)::INT END AS wind_direction_degrees,
    CASE WHEN weather_number(rain) <= -999 THEN NULL
         ELSE weather_number(rain) > 0 END AS raining,
    strptime(regexp_extract(filename, '/(\d{12})-[^/]+-weather\.csv$', 1),
             '%Y%m%d%H%M') AS date,
    filename
FROM read_csv('data/*/*/*/*weather.csv', union_by_name=true, filename=true,
              null_padding=true, normalize_names=true, all_varchar=true)
WHERE regexp_matches(filename, '/\d{12}-[^/]+-weather\.csv$');

CREATE OR REPLACE TABLE event_weather AS WITH
named_weather AS (
    SELECT
        series_code, year, normalize_track_name(event) as event,
        -- Raw event-folder slug + normalized session type: the stable natural key
        -- used to align weather with laps (see 040-laps.sql). `event` above is the
        -- canonical venue name kept for 071-events.sql's per-event stats.
        event as event_folder,
        get_session_type(session) as session_type,
        session, date,
        time_utc_seconds, time_utc,
        AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
            OVER (PARTITION BY filename) as avg_air_temp_raw,
        AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
            OVER (PARTITION BY filename) as avg_track_temp_raw,
        temperature_checked_air(
            series_code,
            air_temp_raw,
            AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                OVER (PARTITION BY filename),
            COALESCE(
                AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
                    OVER (PARTITION BY filename),
                AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                    OVER (PARTITION BY filename)
            )
        )::DECIMAL(6, 2) as air_temp_f,
        temperature_checked_track(
            series_code,
            track_temp_raw,
            AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                OVER (PARTITION BY filename),
            COALESCE(
                AVG(CASE WHEN track_temp_raw BETWEEN -20 AND 200 THEN track_temp_raw END)
                    OVER (PARTITION BY filename),
                AVG(CASE WHEN air_temp_raw BETWEEN -20 AND 160 THEN air_temp_raw END)
                    OVER (PARTITION BY filename)
            )
        )::DECIMAL(6, 2) as track_temp_f,
        filename, pressure_raw, pressure_unit, wind_speed_raw, wind_speed_unit,
        humidity_percent, pressure_inhg,
        wind_speed_mph, wind_direction_degrees, raining,
        -- One logical session per (series, year, event-folder, session-type, start day).
        -- Race-hour-* files share the same filename timestamp prefix → same `date`,
        -- so they collapse into a single race timeline. relative_seconds (computed
        -- below over this partition) then measures elapsed time from race start.
        DENSE_RANK() OVER (ORDER BY series_code, year, event_folder, session_type, date) as session_id,
    FROM event_weather_observations
    ORDER BY session_id, time_utc_seconds
),
weather_with_relative_time AS (
    SELECT
        *,
        -- Calculate relative seconds from session start for easy comparison
        (time_utc_seconds - MIN(time_utc_seconds) OVER (PARTITION BY session_id)) AS relative_seconds
    FROM named_weather
)
SELECT * FROM weather_with_relative_time
-- Deduplicate: keep one weather reading per (session_id, relative_seconds)
-- in case of duplicate weather CSV files
QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id, relative_seconds ORDER BY time_utc_seconds) = 1
ORDER BY session_id, time_utc_seconds;


-- -- Summary statistics
-- SELECT
--     COUNT(DISTINCT year) as years,
--     COUNT(DISTINCT event) as events,
--     COUNT(DISTINCT session) as sessions,
--     COUNT(*) as total_weather_readings,
--     MIN(air_temp_f) as min_air_temp_f,
--     MAX(air_temp_f) as max_air_temp_f,
--     MIN(track_temp_f) as min_track_temp_f,
--     MAX(track_temp_f) as max_track_temp_f,
--     COUNT(CASE WHEN raining THEN 1 END) as rain_readings
-- FROM event_weather;
