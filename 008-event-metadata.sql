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
INSERT INTO event_metadata (series_code, year, event, race_duration_minutes)
SELECT DISTINCT
    series_code,
    year,
    event,
    -- Estimate race duration from max session time (in minutes)
    CAST(EXTRACT(EPOCH FROM MAX(session_time)) / 60 AS INTEGER) as race_duration_minutes
FROM laps
WHERE session = 'race' AND session_time IS NOT NULL
GROUP BY series_code, year, event;

-- Update event types based on duration
UPDATE event_metadata
SET event_type = CASE
    WHEN race_duration_minutes < 180 THEN 'Sprint'  -- Less than 3 hours
    WHEN race_duration_minutes < 360 THEN 'Endurance'  -- 3-6 hours
    ELSE 'Ultra-Endurance'  -- 6+ hours (including 12h, 24h)
END
WHERE race_duration_minutes IS NOT NULL;

-- Update circuit names from event names (best effort)
UPDATE event_metadata
SET circuit_name = CASE
    -- IMSA circuits
    WHEN event LIKE '%daytona%' THEN 'Daytona International Speedway'
    WHEN event LIKE '%sebring%' THEN 'Sebring International Raceway'
    WHEN event LIKE '%laguna%seca%' THEN 'WeatherTech Raceway Laguna Seca'
    WHEN event LIKE '%long%beach%' THEN 'Long Beach Street Circuit'
    WHEN event LIKE '%detroit%' THEN 'Detroit Street Circuit'
    WHEN event LIKE '%watkins%glen%' THEN 'Watkins Glen International'
    WHEN event LIKE '%canadian%tire%' OR event LIKE '%mosport%' THEN 'Canadian Tire Motorsport Park'
    WHEN event LIKE '%road%america%' THEN 'Road America'
    WHEN event LIKE '%virginia%' OR event LIKE '%vir%' THEN 'Virginia International Raceway'
    WHEN event LIKE '%lime%rock%' THEN 'Lime Rock Park'
    WHEN event LIKE '%road%atlanta%' THEN 'Road Atlanta'
    WHEN event LIKE '%petit%' THEN 'Road Atlanta (Petit Le Mans)'
    WHEN event LIKE '%mid%ohio%' THEN 'Mid-Ohio Sports Car Course'
    WHEN event LIKE '%indianapolis%' THEN 'Indianapolis Motor Speedway'
    WHEN event LIKE '%cota%' OR event LIKE '%circuit%americas%' THEN 'Circuit of the Americas'

    -- WEC circuits
    WHEN event LIKE '%le%mans%' THEN 'Circuit de la Sarthe'
    WHEN event LIKE '%spa%' THEN 'Circuit de Spa-Francorchamps'
    WHEN event LIKE '%monza%' THEN 'Autodromo Nazionale di Monza'
    WHEN event LIKE '%imola%' THEN 'Autodromo Enzo e Dino Ferrari'
    WHEN event LIKE '%silverstone%' THEN 'Silverstone Circuit'
    WHEN event LIKE '%fuji%' THEN 'Fuji Speedway'
    WHEN event LIKE '%bahrain%' THEN 'Bahrain International Circuit'
    WHEN event LIKE '%qatar%' THEN 'Lusail International Circuit'
    WHEN event LIKE '%portimao%' THEN 'Autódromo Internacional do Algarve'
    WHEN event LIKE '%interlagos%' THEN 'Autódromo José Carlos Pace'
    WHEN event LIKE '%austin%' THEN 'Circuit of the Americas'

    -- ELMS circuits
    WHEN event LIKE '%barcelona%' THEN 'Circuit de Barcelona-Catalunya'
    WHEN event LIKE '%paul%ricard%' THEN 'Circuit Paul Ricard'
    WHEN event LIKE '%red%bull%ring%' THEN 'Red Bull Ring'
    WHEN event LIKE '%hungaroring%' THEN 'Hungaroring'
    WHEN event LIKE '%monza%' THEN 'Autodromo Nazionale di Monza'

    -- Asian Le Mans circuits
    WHEN event LIKE '%sepang%' THEN 'Sepang International Circuit'
    WHEN event LIKE '%dubai%' THEN 'Dubai Autodrome'
    WHEN event LIKE '%yas%' OR event LIKE '%abu%dhabi%' THEN 'Yas Marina Circuit'
    WHEN event LIKE '%buriram%' THEN 'Chang International Circuit'

    ELSE circuit_name
END;

-- Update countries
UPDATE event_metadata
SET circuit_country = CASE
    WHEN circuit_name LIKE '%Daytona%' OR circuit_name LIKE '%Sebring%'
         OR circuit_name LIKE '%Laguna Seca%' OR circuit_name LIKE '%Road America%'
         OR circuit_name LIKE '%Road Atlanta%' OR circuit_name LIKE '%Watkins Glen%'
         OR circuit_name LIKE '%Mid-Ohio%' OR circuit_name LIKE '%Virginia%'
         OR circuit_name LIKE '%Indianapolis%' OR circuit_name LIKE '%Austin%' THEN 'USA'
    WHEN circuit_name LIKE '%Long Beach%' THEN 'USA'
    WHEN circuit_name LIKE '%Detroit%' THEN 'USA'
    WHEN circuit_name LIKE '%Canadian Tire%' OR circuit_name LIKE '%Mosport%' THEN 'Canada'
    WHEN circuit_name LIKE '%Le Mans%' OR circuit_name LIKE '%Paul Ricard%' THEN 'France'
    WHEN circuit_name LIKE '%Spa%' THEN 'Belgium'
    WHEN circuit_name LIKE '%Monza%' OR circuit_name LIKE '%Imola%' THEN 'Italy'
    WHEN circuit_name LIKE '%Silverstone%' THEN 'United Kingdom'
    WHEN circuit_name LIKE '%Fuji%' THEN 'Japan'
    WHEN circuit_name LIKE '%Bahrain%' THEN 'Bahrain'
    WHEN circuit_name LIKE '%Qatar%' OR circuit_name LIKE '%Lusail%' THEN 'Qatar'
    WHEN circuit_name LIKE '%Portimao%' OR circuit_name LIKE '%Algarve%' THEN 'Portugal'
    WHEN circuit_name LIKE '%Interlagos%' THEN 'Brazil'
    WHEN circuit_name LIKE '%Barcelona%' THEN 'Spain'
    WHEN circuit_name LIKE '%Red Bull Ring%' THEN 'Austria'
    WHEN circuit_name LIKE '%Hungaroring%' THEN 'Hungary'
    WHEN circuit_name LIKE '%Sepang%' THEN 'Malaysia'
    WHEN circuit_name LIKE '%Dubai%' THEN 'UAE'
    WHEN circuit_name LIKE '%Yas Marina%' OR circuit_name LIKE '%Abu Dhabi%' THEN 'UAE'
    WHEN circuit_name LIKE '%Buriram%' OR circuit_name LIKE '%Chang%' THEN 'Thailand'
    ELSE circuit_country
END;

-- Add special notes for notable races
UPDATE event_metadata
SET notes = CASE
    WHEN event LIKE '%24%' AND event LIKE '%daytona%' THEN '24 Hours of Daytona'
    WHEN event LIKE '%12%' AND event LIKE '%sebring%' THEN '12 Hours of Sebring'
    WHEN event LIKE '%petit%' THEN 'Petit Le Mans (10 hours)'
    WHEN event LIKE '%le%mans%' AND series_code = 'wec' THEN '24 Hours of Le Mans'
    WHEN event LIKE '%6%' AND (event LIKE '%spa%' OR event LIKE '%silverstone%') THEN '6 Hours'
    WHEN event LIKE '%8%' AND event LIKE '%bahrain%' THEN '8 Hours of Bahrain'
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
