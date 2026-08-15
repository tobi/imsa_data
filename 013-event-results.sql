-- Race results table from results CSVs
-- Contains finishing positions, gaps, fastest laps, etc.

CREATE OR REPLACE TABLE event_results AS
WITH raw_results AS (
    SELECT
        -- Extract series/year/event from filename
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as series_code,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as year,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3) as event_raw,
        regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 5) as session,
        strptime(
            regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4),
            '%Y%m%d%H%M'
        ) as start_date,
        -- Results data
        CAST(POSITION AS INTEGER) as position,
        TRIM(number) as car,
        STATUS as status,
        CAST(LAPS AS INTEGER) as laps_completed,
        TOTAL_TIME as total_time,
        GAP_FIRST as gap_to_leader,
        GAP_PREVIOUS as gap_to_previous,
        CAST(FL_LAPNUM AS INTEGER) as fastest_lap_number,
        FL_TIME as fastest_lap_time,
        TEAM as team,
        _CLASS as class,
        VEHICLE as chassis
    FROM read_csv(
        "data/*/*/*/*results.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    )
    WHERE POSITION IS NOT NULL
      AND regexp_extract(filename, '^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d{12})\-([^/]+)\-results\.csv$', 4) != ''
)
SELECT
    raw_results.series_code,
    raw_results.series_code || '-' || raw_results.year as series,
    raw_results.year,
    -- Same event naming as 020-event-laps (events.json display name), so
    -- laps and event_results always agree on `event`. normalize_track_name
    -- gave the TRACK name instead, which diverges wherever the display name
    -- is an alias (Canadian Tire Motorsport Park vs Mosport) or the weekend
    -- splits into multiple named events (Watkins Glen 240 / 6 Hours, 2021).
    de.display_name as event,
    -- Per-event race label (e.g. "Race 1") for multi-race weekends; NULL otherwise.
    (SELECT mrm.race_label FROM multi_race_mappings mrm
     WHERE mrm.series_code = raw_results.series_code
       AND mrm.year = raw_results.year
       AND mrm.event_folder = raw_results.event_raw
       AND raw_results.session LIKE mrm.session_prefix || '%') as race_label,
    session,
    start_date,
    position,
    car,
    status,
    laps_completed,
    total_time,
    gap_to_leader,
    gap_to_previous,
    fastest_lap_number,
    fastest_lap_time,
    team,
    class,
    get_canonical_chassis(chassis) as chassis,
    get_homologation(chassis) as homologation,
    get_manufacturer(chassis) as manufacturer
FROM raw_results
INNER JOIN defined_events de
    ON de.series_code = raw_results.series_code
    AND de.year = raw_results.year
    AND de.event_folder = raw_results.event_raw
WHERE is_main_class(raw_results.series_code, raw_results.class)
ORDER BY raw_results.series_code, raw_results.year, event, raw_results.session, raw_results.start_date, raw_results.position;

-- Summary of results by series
SELECT
    series_code,
    COUNT(DISTINCT series || '-' || event || '-' || session) as races,
    COUNT(*) as total_entries,
    COUNT(DISTINCT car) as unique_cars
FROM event_results
WHERE session LIKE '%race%'
GROUP BY series_code
ORDER BY races DESC;
