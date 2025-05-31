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
        air_temp::DOUBLE as air_temp_f,
        track_temp::DOUBLE as track_temp_f,
        humidity::INT as humidity_percent,
        pressure::DOUBLE as pressure_inhg,
        wind_speed::DOUBLE as wind_speed_mph,
        wind_direction::INT as wind_direction_degrees,
        rain::INT as rain_flag,

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
            'AIR_TEMP': 'DOUBLE',
            'TRACK_TEMP': 'DOUBLE',
            'HUMIDITY': 'INT',
            'PRESSURE': 'DOUBLE',
            'WIND_SPEED': 'DOUBLE',
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
        wind_speed_mph, wind_direction_degrees, rain_flag,
        DENSE_RANK() OVER (ORDER BY year, event, session) as session_id,
    FROM event_weather_raw
    ORDER BY session_id, time_utc_seconds
)
SELECT * FROM named_weather ORDER BY session_id, time_utc_seconds;





-- Summary statistics
SELECT
    COUNT(DISTINCT year) as years,
    COUNT(DISTINCT event) as events,
    COUNT(DISTINCT session) as sessions,
    COUNT(*) as total_weather_readings,
    MIN(air_temp_f) as min_air_temp_f,
    MAX(air_temp_f) as max_air_temp_f,
    MIN(track_temp_f) as min_track_temp_f,
    MAX(track_temp_f) as max_track_temp_f,
    AVG(humidity_percent) as avg_humidity_percent,
    COUNT(CASE WHEN rain_flag > 0 THEN 1 END) as rain_readings
FROM event_weather;
