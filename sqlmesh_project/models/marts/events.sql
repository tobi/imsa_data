MODEL (
    name marts.events,
    kind FULL,
    cron '@daily',
    grain (series_code, year, event),
    description 'Event metadata including circuit info, race duration, and event classification.'
);

WITH base_metadata AS (
    SELECT DISTINCT
        series_code,
        year,
        event,
        -- Estimate race duration from max session time (in minutes)
        CAST(MAX(session_time) / 60 AS INTEGER) as race_duration_minutes
    FROM marts.laps
    WHERE session = 'race' AND session_time IS NOT NULL
    GROUP BY series_code, year, event
),

with_event_type AS (
    SELECT
        *,
        CASE
            WHEN race_duration_minutes < 180 THEN 'Sprint'  -- Less than 3 hours
            WHEN race_duration_minutes < 360 THEN 'Endurance'  -- 3-6 hours
            ELSE 'Ultra-Endurance'  -- 6+ hours (including 12h, 24h)
        END AS event_type
    FROM base_metadata
),

with_circuit AS (
    SELECT
        *,
        CASE
            -- IMSA circuits
            WHEN event ILIKE '%daytona%' THEN 'Daytona International Speedway'
            WHEN event ILIKE '%sebring%' THEN 'Sebring International Raceway'
            WHEN event ILIKE '%laguna%seca%' THEN 'WeatherTech Raceway Laguna Seca'
            WHEN event ILIKE '%long%beach%' THEN 'Long Beach Street Circuit'
            WHEN event ILIKE '%detroit%' THEN 'Detroit Street Circuit'
            WHEN event ILIKE '%watkins%glen%' THEN 'Watkins Glen International'
            WHEN event ILIKE '%canadian%tire%' OR event ILIKE '%mosport%' THEN 'Canadian Tire Motorsport Park'
            WHEN event ILIKE '%road%america%' THEN 'Road America'
            WHEN event ILIKE '%virginia%' OR event ILIKE '%vir%' THEN 'Virginia International Raceway'
            WHEN event ILIKE '%lime%rock%' THEN 'Lime Rock Park'
            WHEN event ILIKE '%road%atlanta%' THEN 'Road Atlanta'
            WHEN event ILIKE '%petit%' THEN 'Road Atlanta (Petit Le Mans)'
            WHEN event ILIKE '%mid%ohio%' THEN 'Mid-Ohio Sports Car Course'
            WHEN event ILIKE '%indianapolis%' THEN 'Indianapolis Motor Speedway'
            WHEN event ILIKE '%cota%' OR event ILIKE '%circuit%americas%' THEN 'Circuit of the Americas'
            -- WEC circuits
            WHEN event ILIKE '%le%mans%' THEN 'Circuit de la Sarthe'
            WHEN event ILIKE '%spa%' THEN 'Circuit de Spa-Francorchamps'
            WHEN event ILIKE '%monza%' THEN 'Autodromo Nazionale di Monza'
            WHEN event ILIKE '%imola%' THEN 'Autodromo Enzo e Dino Ferrari'
            WHEN event ILIKE '%silverstone%' THEN 'Silverstone Circuit'
            WHEN event ILIKE '%fuji%' THEN 'Fuji Speedway'
            WHEN event ILIKE '%bahrain%' THEN 'Bahrain International Circuit'
            WHEN event ILIKE '%qatar%' THEN 'Lusail International Circuit'
            WHEN event ILIKE '%portimao%' THEN 'Autodromo Internacional do Algarve'
            WHEN event ILIKE '%interlagos%' THEN 'Autodromo Jose Carlos Pace'
            WHEN event ILIKE '%austin%' THEN 'Circuit of the Americas'
            -- ELMS circuits
            WHEN event ILIKE '%barcelona%' THEN 'Circuit de Barcelona-Catalunya'
            WHEN event ILIKE '%paul%ricard%' THEN 'Circuit Paul Ricard'
            WHEN event ILIKE '%red%bull%ring%' THEN 'Red Bull Ring'
            WHEN event ILIKE '%hungaroring%' THEN 'Hungaroring'
            -- Asian Le Mans circuits
            WHEN event ILIKE '%sepang%' THEN 'Sepang International Circuit'
            WHEN event ILIKE '%dubai%' THEN 'Dubai Autodrome'
            WHEN event ILIKE '%yas%' OR event ILIKE '%abu%dhabi%' THEN 'Yas Marina Circuit'
            WHEN event ILIKE '%buriram%' THEN 'Chang International Circuit'
            ELSE NULL
        END AS circuit_name
    FROM with_event_type
),

with_country AS (
    SELECT
        *,
        CASE
            WHEN circuit_name ILIKE '%Daytona%' OR circuit_name ILIKE '%Sebring%'
                 OR circuit_name ILIKE '%Laguna Seca%' OR circuit_name ILIKE '%Road America%'
                 OR circuit_name ILIKE '%Road Atlanta%' OR circuit_name ILIKE '%Watkins Glen%'
                 OR circuit_name ILIKE '%Mid-Ohio%' OR circuit_name ILIKE '%Virginia%'
                 OR circuit_name ILIKE '%Indianapolis%' OR circuit_name ILIKE '%Austin%'
                 OR circuit_name ILIKE '%Long Beach%' OR circuit_name ILIKE '%Detroit%' THEN 'USA'
            WHEN circuit_name ILIKE '%Canadian Tire%' OR circuit_name ILIKE '%Mosport%' THEN 'Canada'
            WHEN circuit_name ILIKE '%Le Mans%' OR circuit_name ILIKE '%Paul Ricard%' THEN 'France'
            WHEN circuit_name ILIKE '%Spa%' THEN 'Belgium'
            WHEN circuit_name ILIKE '%Monza%' OR circuit_name ILIKE '%Imola%' THEN 'Italy'
            WHEN circuit_name ILIKE '%Silverstone%' THEN 'United Kingdom'
            WHEN circuit_name ILIKE '%Fuji%' THEN 'Japan'
            WHEN circuit_name ILIKE '%Bahrain%' THEN 'Bahrain'
            WHEN circuit_name ILIKE '%Qatar%' OR circuit_name ILIKE '%Lusail%' THEN 'Qatar'
            WHEN circuit_name ILIKE '%Portimao%' OR circuit_name ILIKE '%Algarve%' THEN 'Portugal'
            WHEN circuit_name ILIKE '%Interlagos%' THEN 'Brazil'
            WHEN circuit_name ILIKE '%Barcelona%' THEN 'Spain'
            WHEN circuit_name ILIKE '%Red Bull Ring%' THEN 'Austria'
            WHEN circuit_name ILIKE '%Hungaroring%' THEN 'Hungary'
            WHEN circuit_name ILIKE '%Sepang%' THEN 'Malaysia'
            WHEN circuit_name ILIKE '%Dubai%' THEN 'UAE'
            WHEN circuit_name ILIKE '%Yas Marina%' OR circuit_name ILIKE '%Abu Dhabi%' THEN 'UAE'
            WHEN circuit_name ILIKE '%Buriram%' OR circuit_name ILIKE '%Chang%' THEN 'Thailand'
            ELSE NULL
        END AS circuit_country
    FROM with_circuit
),

with_notes AS (
    SELECT
        *,
        CASE
            WHEN event ILIKE '%24%' AND event ILIKE '%daytona%' THEN '24 Hours of Daytona'
            WHEN event ILIKE '%12%' AND event ILIKE '%sebring%' THEN '12 Hours of Sebring'
            WHEN event ILIKE '%petit%' THEN 'Petit Le Mans (10 hours)'
            WHEN event ILIKE '%le%mans%' AND series_code = 'wec' THEN '24 Hours of Le Mans'
            WHEN event ILIKE '%6%' AND (event ILIKE '%spa%' OR event ILIKE '%silverstone%') THEN '6 Hours'
            WHEN event ILIKE '%8%' AND event ILIKE '%bahrain%' THEN '8 Hours of Bahrain'
            ELSE NULL
        END AS notes
    FROM with_country
)

SELECT
    series_code,
    year,
    event,
    circuit_name,
    circuit_country,
    race_duration_minutes,
    NULL::DECIMAL(10, 2) AS race_distance_km,
    event_type,
    NULL::INTEGER AS round_number,
    notes
FROM with_notes
