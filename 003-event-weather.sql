CREATE TEMP TABLE event_weather_raw AS
    SELECT
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 1) as year,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 2) as event,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 4) as session,

        -- Weather measurements
        time_utc_seconds::BIGINT as time_utc_seconds,
        -- Handle multiple date formats in weather files
        COALESCE(
            TRY_STRPTIME(time_utc_str, '%m/%d/%Y %I:%M:%S %p'),
            TRY_STRPTIME(time_utc_str, '%d-%b-%y %H:%M:%S')
        ) as time_utc,
        air_temp::DECIMAL(6, 2) as air_temp_f,
        track_temp::DECIMAL(6, 2) as track_temp_f,
        humidity::DECIMAL(6, 2) as humidity_percent,
        pressure::DECIMAL(6, 2) as pressure_inhg,
        wind_speed::DECIMAL(6, 2) as wind_speed_mph,
        wind_direction::INT as wind_direction_degrees,
        (rain::INT = 0) as raining,

        -- Date
        strptime(regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 3), '%Y%m%d%H%M') as date,

        filename

    FROM read_csv(
        "data/*/*/*weather.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true,
        types={
            'TIME_UTC_SECONDS': 'BIGINT',
            'TIME_UTC_STR': 'STRING',
            'AIR_TEMP': 'DECIMAL(6, 2)',
            'TRACK_TEMP': 'DECIMAL(6, 2)',
            'HUMIDITY': 'DECIMAL(6, 2)',
            'PRESSURE': 'DECIMAL(6, 2)',
            'WIND_SPEED': 'DECIMAL(6, 2)',
            'WIND_DIRECTION': 'INT',
            'RAIN': 'INT'
        }
    );


CREATE OR REPLACE TABLE event_weather AS WITH
named_weather AS (
    SELECT
        year, event, session, date,
        time_utc_seconds, time_utc,
        air_temp_f, track_temp_f, humidity_percent, pressure_inhg,
        wind_speed_mph, wind_direction_degrees, raining,
        DENSE_RANK() OVER (ORDER BY year, event, session) as session_id,
    FROM event_weather_raw
    ORDER BY session_id, time_utc_seconds
),
weather_with_relative_time AS (
    SELECT
        *,
        -- Calculate relative seconds from session start for easy comparison
        (time_utc_seconds - MIN(time_utc_seconds) OVER (PARTITION BY session_id)) AS relative_seconds
    FROM named_weather
)
SELECT * FROM weather_with_relative_time ORDER BY session_id, time_utc_seconds;


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
