
CREATE TEMP TABLE event_laps_raw AS
    SELECT
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 1) as year,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 2) as event,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 4) as session,

        number as car,
        lap_number as lap,
        driver_name as driver_name,
        _class as class,
        parse_time(lap_time) as lap_time,

        parse_time(elapsed) as session_time,
        parse_time(pit_time) as pit_time,
        parse_time(_hour) as clock_time,

        
        kph::INT as kph,
        top_speed::INT as top_speed,
        crossing_finish_line_in_pit,
        flag_at_fl as flags,

        -- Date
        strptime(regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 3), '%Y%m%d%H%M') as start_date,


        filename

    FROM read_csv(
        "data/*/*/*laps.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true,
        types={
            'number': 'INT',
            'lap_number': 'INT',
            'lap_time': 'STRING',
            'elapsed': 'STRING',
            'pit_time': 'STRING',
            '_hour': 'STRING',
            'kph': 'INT',
            'top_speed': 'INT',
            'flag_at_fl': 'STRING',
        }
    );


CREATE OR REPLACE TABLE event_laps AS WITH
named_laps AS (
    SELECT
        start_date, year, clean_event_name(event) as event, session, lap, lap_time, car, class, session_time, clock_time, pit_time, flags, driver_name, 
        DENSE_RANK() OVER (ORDER BY year, event, session) as session_id,
    FROM event_laps_raw
    ORDER BY session_id, car, lap
),
stint_starts AS (
    SELECT
        *,
        CASE WHEN LAG (driver_name) OVER (PARTITION BY session_id, car ORDER BY session_id, lap) = driver_name THEN 0 ELSE 1
        END AS stint_start
    FROM named_laps
),
stints AS (
    SELECT
        *,
        SUM(stint_start) OVER (PARTITION BY session_id, car, driver_name ORDER BY session_id, lap) AS stint_number
    FROM stint_starts
), laps_with_driver_data AS (
    SELECT
        stints.*,
        d.license,
        d.license_rank,
        d.country as driver_country,
        d.team as team_name
    FROM stints
    LEFT JOIN drivers d ON d.name = stints.driver_name
)
SELECT * FROM laps_with_driver_data ORDER BY session_id, car, lap;


-- SELECT
--     COUNT(DISTINCT driver_name) as drivers,
--     COUNT(DISTINCT class) as classes,
--     COUNT(DISTINCT car) as cars,
--     COUNT(DISTINCT year) as years,
--     COUNT(DISTINCT event) as events,
--     COUNT(DISTINCT session) as sessions,
--     COUNT(*) as total_laps
-- FROM event_laps_raw;

