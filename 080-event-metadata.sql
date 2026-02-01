-- Event Metadata Table
-- Stores additional information about events including race duration, circuit details, etc.
-- This enables analysis by race format and event characteristics

CREATE OR REPLACE TABLE event_metadata (
    series_code VARCHAR,
    year VARCHAR,
    event VARCHAR,
    circuit_name VARCHAR,
    circuit_country VARCHAR,
    race_duration_minutes INTEGER,
    race_distance_km DECIMAL(10, 2),
    event_type VARCHAR,  -- 'Sprint', 'Endurance', 'Ultra-Endurance'
    round_number INTEGER,
    notes VARCHAR,
    PRIMARY KEY (series_code, year, event)
);

-- Extract basic metadata from existing laps data
-- Match various race session naming patterns:
-- IMSA/WEC: 'race', 'race-hour-X'
-- ALMS: 'race-201-hour-X', 'race-202-hour-X', 'race-hour-X'
-- ELMS: 'race'
INSERT INTO event_metadata (series_code, year, event, race_duration_minutes)
SELECT DISTINCT
    series_code,
    year,
    event,
    -- Estimate race duration from max session time (in minutes)
    -- session_time is already in seconds as DECIMAL(10,3)
    CAST(MAX(session_time) / 60 AS INTEGER) as race_duration_minutes
FROM laps
WHERE (session = 'race' OR session LIKE 'race-%') AND session_time IS NOT NULL
GROUP BY series_code, year, event;

-- Update event types based on duration
UPDATE event_metadata
SET event_type = CASE
    WHEN race_duration_minutes < 180 THEN 'Sprint'  -- Less than 3 hours
    WHEN race_duration_minutes < 360 THEN 'Endurance'  -- 3-6 hours
    ELSE 'Ultra-Endurance'  -- 6+ hours (including 12h, 24h)
END
WHERE race_duration_minutes IS NOT NULL;

-- Update circuit names and countries from tracks table
-- Since event names are now normalized to short_name, we can join directly
UPDATE event_metadata
SET
    circuit_name = t.official_name,
    circuit_country = t.country
FROM tracks t
WHERE event_metadata.event = t.short_name;

-- Add special notes for notable races
UPDATE event_metadata
SET notes = CASE
    -- IMSA endurance races
    WHEN race_duration_minutes >= 1400 AND event = 'Daytona' THEN '24 Hours of Daytona'
    WHEN race_duration_minutes >= 700 AND event = 'Sebring' THEN '12 Hours of Sebring'
    WHEN race_duration_minutes >= 550 AND event = 'Road Atlanta' THEN 'Petit Le Mans (10 hours)'
    WHEN race_duration_minutes >= 350 AND event = 'Watkins Glen' THEN '6 Hours of the Glen'
    WHEN race_duration_minutes >= 350 AND event = 'Indianapolis' THEN 'Battle on the Bricks'
    -- WEC endurance races
    WHEN race_duration_minutes >= 1400 AND event = 'Le Mans' THEN '24 Hours of Le Mans'
    WHEN race_duration_minutes >= 450 AND event = 'Bahrain' THEN '8 Hours of Bahrain'
    WHEN race_duration_minutes >= 350 AND event = 'Interlagos' THEN '6 Hours of Sao Paulo'
    WHEN race_duration_minutes >= 350 AND event = 'COTA' THEN '6 Hours of COTA'
    WHEN race_duration_minutes >= 350 AND event = 'Spa' THEN '6 Hours of Spa'
    WHEN race_duration_minutes >= 350 AND event = 'Fuji' THEN '6 Hours of Fuji'
    WHEN race_duration_minutes >= 350 AND event = 'Monza' THEN '6 Hours of Monza'
    WHEN race_duration_minutes >= 350 AND event = 'Imola' THEN '6 Hours of Imola'
    WHEN race_duration_minutes >= 350 AND event = 'Silverstone' THEN '6 Hours of Silverstone'
    WHEN race_duration_minutes >= 350 AND event = 'Portimao' THEN '8 Hours of Portimao'
    WHEN race_duration_minutes >= 350 AND event = 'Losail' THEN '6 Hours of Qatar'
    -- Asian Le Mans Series (4 hour races)
    WHEN series_code = 'alms' AND race_duration_minutes >= 200 AND event = 'Sepang' THEN '4 Hours of Sepang'
    WHEN series_code = 'alms' AND race_duration_minutes >= 200 AND event = 'Dubai' THEN '4 Hours of Dubai'
    WHEN series_code = 'alms' AND race_duration_minutes >= 200 AND event = 'Yas Marina' THEN '4 Hours of Abu Dhabi'
    -- ELMS (4-6 hour races)
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Barcelona' THEN '4 Hours of Barcelona'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Imola' THEN '4 Hours of Imola'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Spa' THEN '4 Hours of Spa'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Paul Ricard' THEN '4 Hours of Le Castellet'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Portimao' THEN '4 Hours of Portimao'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Monza' THEN '4 Hours of Monza'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Mugello' THEN '4 Hours of Mugello'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Aragon' THEN '4 Hours of Aragon'
    WHEN series_code = 'elms' AND race_duration_minutes >= 200 AND event = 'Red Bull Ring' THEN '4 Hours of Red Bull Ring'
    ELSE notes
END;

-- Add laps table with event metadata
CREATE OR REPLACE VIEW laps_with_metadata AS
SELECT
    l.*,
    em.circuit_name,
    em.circuit_country,
    em.race_duration_minutes,
    em.race_distance_km,
    em.event_type,
    em.round_number,
    em.notes as event_notes
FROM laps l
LEFT JOIN event_metadata em
    ON em.series_code = l.series_code
    AND em.year = l.year
    AND em.event = l.event;

-- Summary statistics
SELECT
    event_type,
    COUNT(DISTINCT series_code || '-' || year || '-' || event) as events,
    MIN(race_duration_minutes) as min_duration,
    MAX(race_duration_minutes) as max_duration,
    AVG(race_duration_minutes)::INTEGER as avg_duration,
    STRING_AGG(DISTINCT circuit_country, ', ' ORDER BY circuit_country) as countries
FROM event_metadata
WHERE event_type IS NOT NULL
GROUP BY event_type
ORDER BY min_duration;

.rows
SELECT
    series_code,
    year,
    event,
    circuit_name,
    circuit_country,
    race_duration_minutes,
    event_type,
    notes
FROM event_metadata
ORDER BY series_code, year, event;
