#!/bin/bash
# Data loader for team race results
# Shows positions achieved by teams
# Outputs CSV to stdout for Observable Framework

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_PATH="${IMSA_DB:-$SCRIPT_DIR/../../../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    er.team,
    er.series_code,
    er.year,
    er.event,
    er.session,
    er.start_date,
    er.position,
    er.car,
    er.class,
    er.status,
    er.laps_completed,
    t.track_id,
    t.official_name as track,
    CASE WHEN er.position = 1 THEN 1 ELSE 0 END as is_win,
    CASE WHEN er.position <= 3 THEN 1 ELSE 0 END as is_podium,
    CASE WHEN er.position <= 5 THEN 1 ELSE 0 END as is_top5
FROM event_results er
LEFT JOIN tracks t
    ON list_contains(t.aliases, LOWER(er.event))
    OR LOWER(er.event) = LOWER(t.short_name)
WHERE er.team IS NOT NULL
  AND er.team != ''
  AND er.session LIKE 'race%'
  AND er.event NOT LIKE '%Test%'
  AND er.event NOT LIKE '%test%'
  AND er.position > 0
ORDER BY er.team, er.start_date DESC, er.position;
"
