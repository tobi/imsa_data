-- Load all lap CSV files with basic extraction
CREATE TEMP TABLE event_laps_all_files AS
SELECT
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 1) as series_code,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 2) as year,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 3) as event_folder,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-laps\.csv$', 5) as session_raw,
    -- Normalize session: strip -hour-X suffix
    normalize_session(session_raw) as session_normalized,
    series_code || '-' || year as series,

    TRIM(number) as car,
    lap_number as lap,
    driver_name as driver_name,
    _class as class,
    _group as driver_group,
    team as team,
    parse_time(lap_time) as lap_time,
    parse_time(s1) as lap_time_s1,
    parse_time(s2) as lap_time_s2,
    parse_time(s3) as lap_time_s3,
    parse_time(elapsed) as session_time,
    CASE
        WHEN parse_time(pit_time) >= 86000 THEN NULL
        ELSE parse_time(pit_time)
    END as pit_time,
    parse_time(_hour) as clock_time,
    kph::INT as kph,
    top_speed::INT as top_speed,
    crossing_finish_line_in_pit,
    flag_at_fl as flags,
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
)
WHERE regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d{12})\-([^/]+)\-laps\.csv$', 4) != '';

-- For race sessions, keep only the most complete file per (event, race_number)
-- This collapses race-hour-6, race-hour-12, etc. into one race session
CREATE TEMP TABLE race_files_to_keep AS
WITH race_file_info AS (
    SELECT DISTINCT
        series_code,
        year,
        event_folder,
        session_raw,
        session_normalized,
        -- For race-20X sessions (multi-race), each is a separate race
        -- For plain race sessions, group them together
        CASE
            WHEN session_normalized LIKE 'race-20%' THEN session_normalized
            ELSE 'race'
        END as race_group,
        -- Completeness score: plain 'race' > higher hour numbers
        CASE
            WHEN session_raw = 'race' THEN 999
            WHEN regexp_matches(session_raw, 'hour-[0-9]+$')
            THEN regexp_extract(session_raw, 'hour-([0-9]+)$', 1)::INT
            ELSE 0
        END as completeness,
        start_date,
        filename
    FROM event_laps_all_files
    WHERE session_raw LIKE 'race%'
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY series_code, year, event_folder, race_group
            ORDER BY completeness DESC, start_date DESC
        ) as rank
    FROM race_file_info
)
SELECT filename FROM ranked WHERE rank = 1;

-- Filter to defined events, ignore specified sessions, and keep only selected race files
CREATE TEMP TABLE event_laps_raw AS
SELECT
    e.series_code,
    e.year,
    e.event_folder,
    e.session_normalized as session,
    e.series,
    e.car,
    e.lap,
    e.driver_name,
    e.class,
    e.driver_group,
    e.team,
    e.lap_time,
    e.lap_time_s1,
    e.lap_time_s2,
    e.lap_time_s3,
    e.session_time,
    e.pit_time,
    e.clock_time,
    e.kph,
    e.top_speed,
    e.crossing_finish_line_in_pit,
    e.flags,
    e.start_date,
    e.filename,
    de.display_name as event_display_name
FROM event_laps_all_files e
-- Only include events defined in events.json
INNER JOIN defined_events de
    ON de.series_code = e.series_code
    AND de.year = e.year
    AND de.event_folder = e.event_folder
-- Filter out ignored sessions (e.g., race-201 in WEC/ELMS which are partial data)
WHERE NOT EXISTS (
    SELECT 1 FROM ignored_sessions i
    WHERE i.series_code = e.series_code
      AND e.session_normalized LIKE i.session_pattern || '%'
)
-- For race sessions, only keep the selected files
AND (
    e.session_raw NOT LIKE 'race%'
    OR e.filename IN (SELECT filename FROM race_files_to_keep)
);


CREATE OR REPLACE TABLE event_laps AS WITH
named_laps AS (
    SELECT
        series_code, series, start_date, year,
        -- Get event name from defined_events, add multi-race suffix if applicable
        event_display_name ||
        COALESCE(
            (SELECT ' ' || mrm.event_suffix FROM multi_race_mappings mrm
             WHERE mrm.series_code = event_laps_raw.series_code
               AND event_laps_raw.session LIKE mrm.session_prefix || '%'),
            ''
        ) AS event,
        -- Session type: race, qualifying, practice, warmup, test
        get_session_type(session) AS session,
        lap, lap_time, lap_time_s1, lap_time_s2, lap_time_s3, car, class, team,
        session_time, clock_time, pit_time, flags, driver_name,
        -- Map driver_group to standard license format
        CASE
            WHEN driver_group ILIKE '%platinum%' THEN 'Platinum'
            WHEN driver_group ILIKE '%gold%' THEN 'Gold'
            WHEN driver_group ILIKE '%silver%' THEN 'Silver'
            WHEN driver_group ILIKE '%bronze%' THEN 'Bronze'
            WHEN driver_group ILIKE '%pro%' THEN 'Gold'
            WHEN driver_group ILIKE '%am%' THEN 'Bronze'
            ELSE NULL
        END AS group_license,
        -- Use event_folder + session for session_id to handle multi-race events correctly
        DENSE_RANK() OVER (ORDER BY series_code, year, event_folder, session, start_date) as session_id,
    FROM event_laps_raw
    WHERE is_main_class(series_code, class)
    ORDER BY session_id, car, lap
),
stint_starts AS (
    SELECT
        series_code, series, start_date, year, event, session, lap, lap_time, lap_time_s1, lap_time_s2, lap_time_s3,
        car, class, team, session_time, clock_time, pit_time, flags, driver_name, group_license, session_id,
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
        ranked_stints.series_code,
        ranked_stints.series,
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
        -- Resolve driver_id through alias table for consistent cross-series identity
        resolve_driver_alias(COALESCE(ed.canonical_name, ranked_stints.driver_name)) AS resolved_driver_id,
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
        ranked_stints.group_license AS group_license,
        ed.license AS ed_license,
        ed.license_rank AS ed_license_rank,
        ed.country AS ed_country,
        ed.team AS ed_team,
        ed.chassis AS ed_chassis
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
        lwd.series_code,
        lwd.series,
        lwd.start_date,
        lwd.year,
        lwd.event,
        lwd.session,
        lwd.session_id,
        lwd.session_time,
        lwd.clock_time,
        lwd.session_time_lap_number,
        lwd.car,
        lwd.class,
        lwd.driver_name_raw,
        lwd.driver_name_entry,
        lwd.resolved_driver_id,
        lwd.lap,
        lwd.lap_time,
        lwd.lap_time_s1,
        lwd.lap_time_s2,
        lwd.lap_time_s3,
        lwd.lap_time_driver_rank,
        lwd.lap_time_driver_quartile,
        lwd.pit_time,
        lwd.flags,
        lwd.stint_start,
        lwd.stint_number,
        lwd.stint_lap,
        lwd.stint_team,
        lwd.group_license,
        lwd.ed_license,
        lwd.ed_license_rank,
        lwd.ed_country,
        lwd.ed_team,
        lwd.ed_chassis,
        cl.chassis AS cl_chassis,
        cl.homologation AS cl_homologation,
        cl.manufacturer AS cl_manufacturer,
        dv.canonical_name AS dv_canonical_name,
        dv.preferred_name AS dv_preferred_name,
        dv.license AS dv_license,
        dv.license_rank AS dv_license_rank,
        dv.country AS dv_country,
        dv.team AS dv_team
    FROM laps_with_driver_data lwd
    LEFT JOIN drivers dv
        ON dv.driver_id = lwd.resolved_driver_id
    LEFT JOIN (
        SELECT DISTINCT ON (series_code, year, event, car)
            series_code, year, event, car, chassis, homologation, manufacturer
        FROM chassis_lookup
        ORDER BY series_code, year, event, car, start_date DESC
    ) cl
        ON cl.series_code = lwd.series_code
        AND cl.year = lwd.year
        AND cl.event = lwd.event
        AND cl.car = lwd.car
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
    CASE
        WHEN series_code = 'elms' AND class = 'LMP3' AND cl_homologation = 'GT3' THEN 'LMGT3'
        ELSE class
    END AS class,
    -- Prefer drivers table canonical name (cross-series consistent casing)
    -- over per-session event_drivers name (WEC uses ALL CAPS surnames)
    COALESCE(dv_canonical_name, driver_name_entry, driver_name_raw) AS driver_name,
    resolved_driver_id AS driver_id,
    lap,
    lap_time,
    lap_time_s1,
    lap_time_s2,
    lap_time_s3,
    lap_time_driver_rank,
    lap_time_driver_quartile,
    NULL::INTEGER AS bpillar_quartile,
    CASE
        WHEN session = 'race'
            AND pit_time > 300
            AND lap = MAX(lap) OVER (PARTITION BY session_id, car)
        THEN NULL
        ELSE pit_time
    END AS pit_time,
    flags,
    stint_start,
    stint_number,
    stint_lap,
    COALESCE(ed_license, group_license, dv_license, 'Unknown') AS license,
    COALESCE(ed_license_rank, license_rank(group_license), dv_license_rank, 0) AS license_rank,
    COALESCE(ed_country, dv_country) AS driver_country,
    COALESCE(ed_team, stint_team, dv_team) AS team_name,
    COALESCE(cl_chassis, ed_chassis) AS chassis,
    cl_homologation AS homologation,
    cl_manufacturer AS manufacturer
FROM laps_enriched
ORDER BY session_id, car, lap;
