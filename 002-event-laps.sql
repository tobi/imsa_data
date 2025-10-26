
CREATE TEMP TABLE event_laps_raw AS
    SELECT
        -- Extract series from path: data/{series}/{year}/{event}/{timestamp}-{session}-laps.csv
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 1) as series_code,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 2) as year,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 3) as event,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 5) as session,
        series_code || '-' || year as series,

        TRIM(number) as car,
        lap_number as lap,
        driver_name as driver_name,
        _class as class,
        team as team,
        parse_time(lap_time) as lap_time,
        parse_time(s1) as lap_time_s1,
        parse_time(s2) as lap_time_s2,
        parse_time(s3) as lap_time_s3,

        parse_time(elapsed) as session_time,
        parse_time(pit_time) as pit_time,
        parse_time(_hour) as clock_time,


        kph::INT as kph,
        top_speed::INT as top_speed,
        crossing_finish_line_in_pit,
        flag_at_fl as flags,

        -- Date
        strptime(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 4),
            '%Y%m%d%H%M'
        ) as start_date,


        filename

    FROM read_csv(
        "data/*/*/*/*laps.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true,
        types={
            'number': 'VARCHAR',
            'lap_number': 'INT',
            'lap_time': 'STRING',
            's1': 'STRING',
            's2': 'STRING',
            's3': 'STRING',
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
        series_code, series, start_date, year, clean_event_name(event) as event, session, lap, lap_time, lap_time_s1, lap_time_s2, lap_time_s3, car, class, team, session_time, clock_time, pit_time, flags, driver_name,
        DENSE_RANK() OVER (ORDER BY series_code, year, event, session, start_date) as session_id,
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
stint_counters AS (
    SELECT
        *,
        SUM(stint_start) OVER (PARTITION BY session_id, car ORDER BY session_id, lap) AS stint_number
    FROM stint_starts
),
stints AS (
    SELECT
        stint_counters.*,
        (ROW_NUMBER() OVER (PARTITION BY session_id, car, stint_number ORDER BY session_id, lap) - 1)::INTEGER AS stint_lap
    FROM stint_counters
),
leader_laps AS (
    SELECT
        session_id,
        lap,
        MIN(session_time) AS leader_session_time
    FROM stint_counters
    WHERE session_time IS NOT NULL
    GROUP BY session_id, lap
),
ranked_stints AS (
    SELECT
        stints.*,
        DENSE_RANK() OVER (
            PARTITION BY session_id, driver_name
            ORDER BY lap_time NULLS LAST
        ) AS lap_time_driver_rank_raw,
        NTILE(4) OVER (
            PARTITION BY session_id, driver_name
            ORDER BY lap_time NULLS LAST
        ) AS lap_time_driver_quartile_raw,
        COALESCE(
            (
                SELECT MAX(ll.lap)
                FROM leader_laps ll
                WHERE ll.session_id = stints.session_id
                  AND ll.leader_session_time <= stints.session_time
            ),
            0
        )::INTEGER AS session_time_lap_number
    FROM stints
), laps_with_driver_data AS (
    SELECT
        ranked_stints.start_date,
        ranked_stints.year,
        ranked_stints.event,
        ranked_stints.session,
        ranked_stints.session_id,
        ranked_stints.session_time,
        ranked_stints.clock_time,
        ranked_stints.session_time_lap_number,
        ranked_stints.car,
        ranked_stints.class,
        ranked_stints.driver_name AS driver_name_raw,
        COALESCE(ed.canonical_name, ranked_stints.driver_name) AS driver_name_entry,
        CASE
            WHEN ed.driver_id IS NOT NULL THEN ed.driver_id
            ELSE LOWER(REGEXP_REPLACE(TRIM(ranked_stints.driver_name), '\\s+', ' '))
        END AS resolved_driver_id,
        ranked_stints.lap,
        ranked_stints.lap_time,
        ranked_stints.lap_time_s1,
        ranked_stints.lap_time_s2,
        ranked_stints.lap_time_s3,
        CASE
            WHEN ranked_stints.lap_time IS NULL THEN NULL
            ELSE ranked_stints.lap_time_driver_rank_raw
        END AS lap_time_driver_rank,
        CASE
            WHEN ranked_stints.lap_time IS NULL THEN NULL
            ELSE ranked_stints.lap_time_driver_quartile_raw
        END AS lap_time_driver_quartile,
        ranked_stints.pit_time,
        ranked_stints.flags,
        ranked_stints.stint_start,
        ranked_stints.stint_number,
        ranked_stints.stint_lap,
        ranked_stints.team AS stint_team,
        ed.license AS ed_license,
        ed.license_rank AS ed_license_rank,
        ed.country AS ed_country,
        ed.team AS ed_team
    FROM ranked_stints
    LEFT JOIN event_drivers ed
        ON ed.series_code = ranked_stints.series_code
        AND ed.year = ranked_stints.year
        AND ed.event = ranked_stints.event
        AND ed.session = ranked_stints.session
        AND ed.car = ranked_stints.car
        AND ed.start_date = ranked_stints.start_date
        AND LOWER(TRIM(ed.name)) = LOWER(TRIM(ranked_stints.driver_name))
), laps_enriched AS (
    SELECT
        lwd.*,
        dv.canonical_name AS dv_canonical_name,
        dv.preferred_name AS dv_preferred_name,
        dv.license AS dv_license,
        dv.license_rank AS dv_license_rank,
        dv.country AS dv_country,
        dv.team AS dv_team
    FROM laps_with_driver_data lwd
    LEFT JOIN drivers dv
        ON dv.driver_id = lwd.resolved_driver_id
)
SELECT
    series_code,
    series,
    start_date,
    year,
    event,
    session,
    session_id,
    session_time,
    clock_time,
    session_time_lap_number,
    car,
    class,
    COALESCE(driver_name_entry, dv_canonical_name, driver_name_raw) AS driver_name,
    resolved_driver_id AS driver_id,
    lap,
    lap_time,
    lap_time_s1,
    lap_time_s2,
    lap_time_s3,
    lap_time_driver_rank,
    lap_time_driver_quartile,
    NULL::INTEGER AS bpillar_quartile,
    pit_time,
    flags,
    stint_start,
    stint_number,
    stint_lap,
    COALESCE(ed_license, dv_license) AS license,
    COALESCE(ed_license_rank, dv_license_rank) AS license_rank,
    COALESCE(ed_country, dv_country) AS driver_country,
    COALESCE(ed_team, stint_team, dv_team) AS team_name
FROM laps_enriched
ORDER BY session_id, car, lap;


-- SELECT
--     COUNT(DISTINCT driver_name) as drivers,
--     COUNT(DISTINCT class) as classes,
--     COUNT(DISTINCT car) as cars,
--     COUNT(DISTINCT year) as years,
--     COUNT(DISTINCT event) as events,
--     COUNT(DISTINCT session) as sessions,
--     COUNT(*) as total_laps
-- FROM event_laps_raw;
