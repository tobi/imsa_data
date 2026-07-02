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

-- Microsector timing points (only present in AnalysisEnduranceWithSections_*
-- CSVs — currently WEC/Le Mans; most series/sessions have none of these
-- columns at all, so this whole block is a no-op for them).
--
-- Every "<name>_time"/"<name>_elapsed" column pair becomes one array element
-- {name, timing, elapsed, meters} in a per-lap JSON array, ordered by
-- elapsed (i.e. track order). `timing` = time to cross this segment
-- (interval); `elapsed` = cumulative lap time at this point (matches
-- FL_elapsed == lap_time); `meters` = cumulative distance around the lap for
-- this point, from track_atlas_points — NULL when track-atlas has no
-- geometry for that specific point (e.g. Le Mans's SCL1/SCL2/SCLC/IP2/
-- FORDOUT aren't in the upstream slow-zone dataset yet).
CREATE TEMP TABLE microsectors_raw AS
WITH cols_as_varchar AS (
    SELECT
        filename,
        regexp_extract(filename, '^data/([^/]+)/\d{4}/\d\d\-([^/]+)/', 1) AS series_code,
        regexp_extract(filename, '^data/([^/]+)/\d{4}/\d\d\-([^/]+)/', 2) AS event_folder,
        TRIM(number) AS car,
        lap_number AS lap,
        COLUMNS(c -> regexp_matches(c, '(_time|_elapsed)$') AND c NOT IN ('lap_time', 'pit_time'))::VARCHAR
    FROM read_csv(
        "data/*/*/*/*laps.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true,
        types={'number': 'VARCHAR', 'lap_number': 'INT'}
    )
),
times_long AS (
    UNPIVOT cols_as_varchar
    ON COLUMNS(c -> c LIKE '%\_time' ESCAPE '\')
    INTO NAME sector_col VALUE time_raw
),
elapsed_long AS (
    UNPIVOT cols_as_varchar
    ON COLUMNS(c -> c LIKE '%\_elapsed' ESCAPE '\')
    INTO NAME sector_col_elapsed VALUE elapsed_raw
),
matched AS (
    SELECT
        t.filename, t.series_code, t.event_folder, t.car, t.lap,
        -- Normalize e.g. "a71" -> "A71" so it can be matched against
        -- track_atlas_points.point_key (which strips hyphens from "A7-1").
        UPPER(REPLACE(t.sector_col, '_time', '')) AS sector_name,
        parse_time(t.time_raw) AS timing,
        parse_time(e.elapsed_raw) AS elapsed
    FROM times_long t
    JOIN elapsed_long e
        ON e.filename = t.filename AND e.car = t.car AND e.lap = t.lap
       AND e.sector_col_elapsed = REPLACE(t.sector_col, '_time', '_elapsed')
    WHERE t.time_raw IS NOT NULL
),
matched_with_meters AS (
    SELECT
        m.filename, m.car, m.lap, m.sector_name, m.timing, m.elapsed,
        tap.meters
    FROM matched m
    LEFT JOIN tracks t ON t.short_name = normalize_track_name(m.event_folder)
    LEFT JOIN track_atlas_points tap
        ON tap.imsa_slug = t.track_id
        AND tap.series_code = m.series_code
        AND tap.point_key = REGEXP_REPLACE(m.sector_name, '[^A-Za-z0-9]', '', 'g')
)
SELECT
    filename,
    car,
    lap,
    to_json(
        list(
            struct_pack(name := sector_name, timing := timing, elapsed := elapsed, meters := meters)
            ORDER BY elapsed
        )
    ) AS microsectors_json,
    COUNT(*) > 0 AS has_microsectors
FROM matched_with_meters
GROUP BY filename, car, lap;



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
    de.display_name as event_display_name,
    COALESCE(ms.microsectors_json, NULL) as microsectors_json,
    COALESCE(ms.has_microsectors, false) as has_microsectors
FROM event_laps_all_files e
-- Only include events defined in events.json
INNER JOIN defined_events de
    ON de.series_code = e.series_code
    AND de.year = e.year
    AND de.event_folder = e.event_folder
LEFT JOIN microsectors_raw ms
    ON ms.filename = e.filename
    AND ms.car = e.car
    AND ms.lap = e.lap
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
        -- Clean event name (no race suffix); the race identity lives in race_label.
        event_display_name AS event,
        -- Raw folder slug: stable natural-key component for the weather join (040-laps.sql).
        event_folder,
        -- Per-event race label (e.g. "Race 1") for multi-race weekends; NULL otherwise.
        (SELECT mrm.race_label FROM multi_race_mappings mrm
         WHERE mrm.series_code = event_laps_raw.series_code
           AND mrm.year = event_laps_raw.year
           AND mrm.event_folder = event_laps_raw.event_folder
           AND event_laps_raw.session LIKE mrm.session_prefix || '%') AS race_label,
        -- Session type: race, qualifying, practice, warmup, test
        get_session_type(session) AS session,
        lap, lap_time, lap_time_s1, lap_time_s2, lap_time_s3, car, class, team,
        session_time, clock_time, pit_time, flags, driver_name,
        microsectors_json, has_microsectors,
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
        series_code, series, start_date, year, event, event_folder, race_label, session, lap, lap_time, lap_time_s1, lap_time_s2, lap_time_s3,
        car, class, team, session_time, clock_time, pit_time, flags, driver_name, group_license, session_id,
        microsectors_json, has_microsectors,
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
        ranked_stints.event_folder,
        ranked_stints.race_label,
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
        ranked_stints.microsectors_json,
        ranked_stints.has_microsectors,
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
        lwd.event_folder,
        lwd.race_label,
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
        lwd.microsectors_json,
        lwd.has_microsectors,
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
    laps_enriched.series_code,
    series,
    start_date,
    year,
    event,
    event_folder,
    race_label,
    session,
    session_id,
    session_time,
    clock_time,
    session_time_lap_number,
    car,
    CASE
        WHEN laps_enriched.series_code = 'elms' AND class = 'LMP3' AND cl_homologation = 'GT3' THEN 'LMGT3'
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
    -- Real sector distances (meters) from track-atlas, keyed by track +
    -- series (Sebring has distinct wec/imsa sector splits). NULL when
    -- track-atlas has no geometry for this track (see track_atlas_gaps).
    tap_sectors.s1_meters,
    tap_sectors.s2_meters,
    tap_sectors.s3_meters,
    has_microsectors,
    microsectors_json,
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
    -- Resolve team name to best casing via canonical_teams lookup
    COALESCE(
        ct.canonical_team,
        ed_team, stint_team, dv_team
    ) AS team_name,
    COALESCE(cl_chassis, ed_chassis) AS chassis,
    cl_homologation AS homologation,
    cl_manufacturer AS manufacturer
FROM laps_enriched
LEFT JOIN tracks lap_track ON lap_track.short_name = normalize_track_name(laps_enriched.event_folder)
LEFT JOIN (
    SELECT
        imsa_slug, series_code,
        MAX(CASE WHEN label = 'S1' THEN length_m END) AS s1_meters,
        MAX(CASE WHEN label = 'S2' THEN length_m END) AS s2_meters,
        MAX(CASE WHEN label = 'S3' THEN length_m END) AS s3_meters
    FROM track_atlas_sectors
    WHERE kind = 'timing_sectors'
    GROUP BY imsa_slug, series_code
) tap_sectors
    ON tap_sectors.imsa_slug = lap_track.track_id
    AND tap_sectors.series_code = laps_enriched.series_code
-- Join canonical team names: pick best casing per normalized team key
-- Prefers mixed case over ALL CAPS, shorter over longer, most frequent
LEFT JOIN (
    SELECT DISTINCT ON (team_key) team_key, team AS canonical_team
    FROM (
        SELECT
            LOWER(REGEXP_REPLACE(TRIM(team), '\s+', ' ')) AS team_key,
            REGEXP_REPLACE(TRIM(team), '\s+', ' ') AS team,
            -- Score: penalize ALL CAPS (3+ consecutive uppercase = WEC style)
            CASE WHEN team ~ '[A-Z]{3}' THEN 1 ELSE 0 END AS caps_penalty,
            COUNT(*) AS freq
        FROM event_drivers
        WHERE team IS NOT NULL
        GROUP BY team_key, team, caps_penalty
    )
    ORDER BY team_key, caps_penalty, freq DESC, LENGTH(team)
) ct ON ct.team_key = LOWER(REGEXP_REPLACE(TRIM(COALESCE(laps_enriched.ed_team, laps_enriched.stint_team, laps_enriched.dv_team)), '\s+', ' '))
-- Deduplicate: keep one row per (session_id, car, lap) in case of duplicate source files
QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id, car, lap ORDER BY session_id) = 1
ORDER BY session_id, car, lap;
