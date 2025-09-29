-- Convenience views for season-specific analysis.
-- Update this file when new seasons are added to the dataset.

CREATE OR REPLACE VIEW laps_2021 AS
SELECT *
FROM laps
WHERE year = '2021' AND session = 'race';

CREATE OR REPLACE VIEW laps_2022 AS
SELECT *
FROM laps
WHERE year = '2022' AND session = 'race';

CREATE OR REPLACE VIEW laps_2023 AS
SELECT *
FROM laps
WHERE year = '2023' AND session = 'race';

CREATE OR REPLACE VIEW laps_2024 ASå
SELECT *
FROM laps
WHERE year = '2024' AND session = 'race';

CREATE OR REPLACE VIEW laps_2025 AS
SELECT *
FROM laps
WHERE year = '2025' AND session = 'race';

-- Summary of each session by season/event with distinct car, driver, class counts
CREATE OR REPLACE VIEW seasons AS
WITH event_first_sessions AS (
    SELECT
        year,
        event,
        MIN(start_date) AS event_start_date
    FROM laps
    GROUP BY year, event
)
SELECT
    CAST(efs.event_start_date AS DATE) AS date,
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
        ELSE MIN(l.start_date) + (MAX(l.session_time) * INTERVAL 1 SECOND)
    END AS session_end,
    MAX(l.lap) AS total_laps,
    STRING_AGG(
        DISTINCT TRIM(l.flags),
        ', '
        ORDER BY TRIM(l.flags)
    ) FILTER (
        WHERE l.flags IS NOT NULL
          AND TRIM(l.flags) <> ''
          AND UPPER(TRIM(l.flags)) <> 'GF'
    ) AS flags
FROM laps l
JOIN event_first_sessions efs
    ON efs.year = l.year
    AND efs.event = l.event
GROUP BY
    efs.event_start_date,
    l.session_id,
    l.year,
    l.event,
    l.session
ORDER BY
    efs.event_start_date,
    l.session_id;
