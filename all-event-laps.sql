
CREATE OR REPLACE MACRO parse_time (lap) AS (
    CASE
        WHEN LENGTH(lap) - LENGTH(REPLACE(lap, ':', '')) = 2 THEN 
            strptime(lap, '%-H:%M:%S.%g')
        WHEN LENGTH(lap) - LENGTH(REPLACE(lap, ':', '')) = 0 THEN 
            strptime(lap, '%-S.%g')         
        ELSE 
            strptime(lap, '%-M:%S.%g')
    END::TIME
);


CREATE OR REPLACE MACRO format_lap (total_seconds) AS (
    printf(
        '%d:%06.3f',
        CAST(FLOOR(total_seconds / 60) AS INTEGER),
        total_seconds - FLOOR(total_seconds / 60) * 60
    )
);

CREATE TEMP TABLE event_laps_raw AS 
    SELECT
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 1) as year,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 2) as event,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 4) as session,            

        number::INT as car,
        lap_number::INT as lap,
        driver_name as driver_name,
        _class as class,
        parse_time ("lap_time") AS lap_time,
        parse_time ("elapsed") AS session_time,
        parse_time ("pit_time") AS pit_time,
        parse_time ("_hour") AS time,
        kph::INT as kph,
        top_speed::INT as top_speed,
        crossing_finish_line_in_pit,
        flag_at_fl as flags,
        parse_time(pit_time) as pit_time,
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
        }
    );


CREATE OR REPLACE TABLE event_laps AS WITH 
named_laps AS (
    SELECT 
        year, event, session, lap, lap_time, driver_name, car, class, session_time, time, pit_time, top_speed, crossing_finish_line_in_pit, flags,
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
        SUM(stint_start) OVER (PARTITION BY session_id, car ORDER BY session_id, lap) AS stint_number
    FROM stint_starts
)
SELECT * FROM stint_starts ORDER BY session_id, car, lap;


SELECT 
    COUNT(DISTINCT driver_name) as drivers,
    COUNT(DISTINCT class) as classes,
    COUNT(DISTINCT car) as cars,
    COUNT(DISTINCT year) as years,
    COUNT(DISTINCT event) as events,
    COUNT(DISTINCT session) as sessions,
    COUNT(*) as total_laps
FROM event_laps_raw;

