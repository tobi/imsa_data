-- Convenience views for season-specific and series-specific analysis.
-- Update this file when new seasons or series are added to the dataset.

-- Series-specific views (all sessions)
CREATE OR REPLACE VIEW laps_imsa AS SELECT * FROM laps WHERE series_code = 'imsa';
CREATE OR REPLACE VIEW laps_wec AS SELECT * FROM laps WHERE series_code = 'wec';
CREATE OR REPLACE VIEW laps_elms AS SELECT * FROM laps WHERE series_code = 'elms';
CREATE OR REPLACE VIEW laps_alms AS SELECT * FROM laps WHERE series_code = 'alms';

-- Series + Year views (race sessions only)
CREATE OR REPLACE VIEW laps_imsa_2021 AS SELECT * FROM laps WHERE series = 'imsa-2021' AND session = 'race';
CREATE OR REPLACE VIEW laps_imsa_2022 AS SELECT * FROM laps WHERE series = 'imsa-2022' AND session = 'race';
CREATE OR REPLACE VIEW laps_imsa_2023 AS SELECT * FROM laps WHERE series = 'imsa-2023' AND session = 'race';
CREATE OR REPLACE VIEW laps_imsa_2024 AS SELECT * FROM laps WHERE series = 'imsa-2024' AND session = 'race';
CREATE OR REPLACE VIEW laps_imsa_2025 AS SELECT * FROM laps WHERE series = 'imsa-2025' AND session = 'race';

CREATE OR REPLACE VIEW laps_wec_2024 AS SELECT * FROM laps WHERE series = 'wec-2024' AND session = 'race';
CREATE OR REPLACE VIEW laps_wec_2025 AS SELECT * FROM laps WHERE series = 'wec-2025' AND session = 'race';

CREATE OR REPLACE VIEW laps_elms_2024 AS SELECT * FROM laps WHERE series = 'elms-2024' AND session = 'race';
CREATE OR REPLACE VIEW laps_elms_2025 AS SELECT * FROM laps WHERE series = 'elms-2025' AND session = 'race';

CREATE OR REPLACE VIEW laps_alms_2024 AS SELECT * FROM laps WHERE series = 'alms-2024' AND session = 'race';
CREATE OR REPLACE VIEW laps_alms_2025 AS SELECT * FROM laps WHERE series = 'alms-2025' AND session = 'race';

-- Legacy year-only views (backward compatibility - shows all series for that year)
CREATE OR REPLACE VIEW laps_2021 AS SELECT * FROM laps WHERE year = '2021' AND session = 'race';
CREATE OR REPLACE VIEW laps_2022 AS SELECT * FROM laps WHERE year = '2022' AND session = 'race';
CREATE OR REPLACE VIEW laps_2023 AS SELECT * FROM laps WHERE year = '2023' AND session = 'race';
CREATE OR REPLACE VIEW laps_2024 AS SELECT * FROM laps WHERE year = '2024' AND session = 'race';
CREATE OR REPLACE VIEW laps_2025 AS SELECT * FROM laps WHERE year = '2025' AND session = 'race';

-- Summary of each session by series/season/event with distinct car, driver, class counts
CREATE OR REPLACE VIEW seasons AS
WITH event_first_sessions AS (
    SELECT
        series_code,
        year,
        event,
        MIN(start_date) AS event_start_date
    FROM laps
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
FROM laps l
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
    l.session_id;
