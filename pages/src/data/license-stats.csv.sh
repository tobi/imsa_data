#!/bin/bash
# License tier performance statistics
# Compares Platinum/Gold/Silver/Bronze driver speeds

DB_PATH="${IMSA_DB:-../output/imsa.duckdb}"

duckdb "$DB_PATH" -csv -c "
SELECT
    series_code,
    class,
    license,
    COUNT(DISTINCT driver) as drivers,
    COUNT(*) as total_laps,
    COUNT(CASE WHEN bpillar_quartile = 1 THEN 1 END) as q1_laps,
    COUNT(CASE WHEN bpillar_quartile = 2 THEN 1 END) as q2_laps,
    ROUND(AVG(CASE WHEN bpillar_quartile IN (1,2) THEN lap_time END), 3) as avg_pace,
    ROUND(MIN(CASE WHEN bpillar_quartile = 1 THEN lap_time END), 3) as best_lap,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY lap_time) FILTER (WHERE bpillar_quartile IN (1,2)), 3) as p25_pace,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY lap_time) FILTER (WHERE bpillar_quartile IN (1,2)), 3) as median_pace
FROM laps l
WHERE session = 'race'
  AND license IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM events e
    WHERE e.series_code = l.series_code
      AND e.year = l.year
      AND e.event_name = l.event
      AND (e.event_name LIKE '%Test%' OR e.event_name LIKE '%test%')
  )
GROUP BY series_code, class, license
HAVING COUNT(*) > 100
ORDER BY series_code, class,
    CASE license
        WHEN 'Platinum' THEN 1
        WHEN 'Gold' THEN 2
        WHEN 'Silver' THEN 3
        WHEN 'Bronze' THEN 4
        ELSE 5
    END;
"
