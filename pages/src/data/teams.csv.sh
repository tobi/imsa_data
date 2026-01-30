#!/bin/bash
# Data loader for team directory
# Aggregates team stats from event_driver_summary
# Outputs CSV to stdout for Observable Framework

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
WITH team_stats AS (
    SELECT
        team,
        series_code,
        year,
        event,
        car,
        class,
        driver,
        laps
    FROM event_driver_summary
    WHERE team IS NOT NULL
      AND team != ''
      AND event NOT LIKE '%Test%'
      AND event NOT LIKE '%test%'
),
team_aggregates AS (
    SELECT
        team,
        COUNT(DISTINCT driver) as unique_drivers,
        COUNT(DISTINCT (series_code || '-' || year || '-' || event)) as total_events,
        COUNT(DISTINCT series_code) as series_count,
        SUM(laps) as total_laps,
        MIN(year) as first_year,
        MAX(year) as last_year,
        -- Get most recent class
        (SELECT class FROM team_stats ts2
         WHERE ts2.team = team_stats.team
         ORDER BY year DESC, event DESC LIMIT 1) as last_class,
        -- Get most recent series
        (SELECT series_code FROM team_stats ts2
         WHERE ts2.team = team_stats.team
         ORDER BY year DESC, event DESC LIMIT 1) as last_series
    FROM team_stats
    GROUP BY team
)
SELECT
    team,
    unique_drivers,
    total_events,
    series_count,
    total_laps,
    first_year,
    last_year,
    last_class,
    last_series
FROM team_aggregates
ORDER BY total_events DESC, team;
"
