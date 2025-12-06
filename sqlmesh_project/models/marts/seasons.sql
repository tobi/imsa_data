MODEL (
    name marts.seasons,
    kind FULL,
    cron '@daily',
    grain (session_id),
    description 'Summary of each session by series/season/event with distinct car, driver, class counts.'
);

WITH event_first_sessions AS (
    SELECT
        series_code,
        year,
        event,
        MIN(start_date) AS event_start_date
    FROM marts.laps_with_bpillar
    GROUP BY series_code, year, event
)

SELECT
    CAST(efs.event_start_date AS DATE) AS date,
    l.series_code,
    l.series,
    l.session_id,
    l.year AS season,
    l.event,
    l.session,
    COUNT(DISTINCT l.car) AS cars,
    COUNT(DISTINCT l.driver_name) AS drivers,
    STRING_AGG(DISTINCT l.class, ', ' ORDER BY l.class) AS classes,
    MIN(l.start_date) AS session_start,
    CASE
        WHEN MAX(l.session_time) IS NULL THEN NULL
        ELSE MIN(l.start_date) + (CAST(MAX(l.session_time) AS BIGINT) * INTERVAL 1 SECOND)
    END AS session_end,
    MAX(l.lap) AS total_laps,
    COUNT(CASE WHEN l.raining THEN 1 END) AS rain_laps,
    STRING_AGG(
        DISTINCT TRIM(l.flags),
        ', '
        ORDER BY TRIM(l.flags)
    ) FILTER (
        WHERE l.flags IS NOT NULL
          AND TRIM(l.flags) <> ''
          AND UPPER(TRIM(l.flags)) <> 'GF'
    ) AS flags
FROM marts.laps_with_bpillar l
JOIN event_first_sessions efs
    ON efs.series_code = l.series_code
    AND efs.year = l.year
    AND efs.event = l.event
GROUP BY
    efs.event_start_date,
    l.series_code,
    l.series,
    l.session_id,
    l.year,
    l.event,
    l.session
ORDER BY
    efs.event_start_date,
    l.session_id
