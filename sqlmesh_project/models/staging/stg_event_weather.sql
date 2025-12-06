MODEL (
    name staging.stg_event_weather,
    kind FULL,
    cron '@daily',
    grain (session_id, time_utc_seconds),
    description 'Staged weather data with relative time calculations for lap matching.'
);

WITH raw_weather AS (
    SELECT
        -- Extract series from path: data/{series}/{year}/{event}/{timestamp}-{session}-weather.csv
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 1) as series_code,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 2) as year,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 3) as event_raw,
        regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 5) as session,

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
        strptime(
            regexp_extract(filename, '^[^/]*/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-weather\.csv$', 4),
            '%Y%m%d%H%M'
        ) as date,

        filename

    FROM read_csv(
        "../data/*/*/*/*weather.csv",
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
    )
),

named_weather AS (
    SELECT
        series_code,
        year,
        @clean_event_name(event_raw) as event,
        session,
        date,
        time_utc_seconds,
        time_utc,
        air_temp_f,
        track_temp_f,
        humidity_percent,
        pressure_inhg,
        wind_speed_mph,
        wind_direction_degrees,
        raining,
        DENSE_RANK() OVER (ORDER BY series_code, year, event_raw, session) as session_id
    FROM raw_weather
    ORDER BY session_id, time_utc_seconds
),

weather_with_relative_time AS (
    SELECT
        *,
        -- Calculate relative seconds from session start for easy comparison
        (time_utc_seconds - MIN(time_utc_seconds) OVER (PARTITION BY session_id)) AS relative_seconds
    FROM named_weather
)

SELECT * FROM weather_with_relative_time ORDER BY session_id, time_utc_seconds
