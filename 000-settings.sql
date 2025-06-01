.columns
.large_number_rendering all
.bail on

.highlight_colors layout red
.highlight_colors column_type gray
.highlight_colors column_name yellow bold_underline
.highlight_colors numeric_value cyan underline
.highlight_colors temporal_value red bold
.highlight_colors string_value green bold
.highlight_colors footer gray


CREATE OR REPLACE MACRO clean_event_name(event_name) AS (
    CASE 
        WHEN event_name ILIKE '%watkins%' OR event_name ILIKE '%wgi%' THEN 'Watkins Glen'
        WHEN event_name ILIKE '%belle-isle%' THEN 'Belle Isle'
        WHEN event_name ILIKE '%canadian-tire%' THEN 'Canadian Tire Motorsport Park'
        WHEN event_name ILIKE '%daytona%' THEN 'Daytona'
        WHEN event_name ILIKE '%detroit%' THEN 'Detroit'
        WHEN event_name ILIKE '%sebring%' THEN 'Sebring'
        WHEN event_name ILIKE '%indianapolis%' OR event_name ILIKE '%battle-on-the-bricks%' THEN 'Indianapolis'
        WHEN event_name ILIKE '%lime-rock%' THEN 'Lime Rock Park'
        WHEN event_name ILIKE '%long-beach%' THEN 'Long Beach'
        WHEN event_name ILIKE '%mid-ohio%' THEN 'Mid-Ohio'
        WHEN event_name ILIKE '%road-america%' THEN 'Road America'
        WHEN event_name ILIKE '%road-atlanta%' THEN 'Road Atlanta'
        WHEN event_name ILIKE '%roar%' THEN 'Daytona (Roar Test)'
        WHEN event_name ILIKE '%laguna-seca%' THEN 'Laguna Seca'
        WHEN event_name ILIKE '%virginia%' THEN 'Virginia International Raceway'
        WHEN event_name ILIKE '%february%' AND event_name ILIKE '%test%' THEN 'Sebring (February Test)'
        ELSE ERROR('Unknown track, add to mapping: ' || event_name)
    END
);

CREATE OR REPLACE MACRO license_rank(license) AS (
    CASE
        WHEN UPPER(license[1:1]) = 'P' THEN 5 -- Platinum
        WHEN UPPER(license[1:1]) = 'G' THEN 4 -- Gold
        WHEN UPPER(license[1:1]) = 'S' THEN 3 -- Silver
        WHEN UPPER(license[1:1]) = 'B' THEN 2 -- Bronze
        ELSE 0
    END
);

CREATE OR REPLACE MACRO parse_time (t) AS (
    EXTRACT(EPOCH FROM(
        COALESCE(
            TRY_STRPTIME(t,             '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:'  || t,   '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:00:'|| t,  '%-H:%M:%S.%g'),
            TRY_STRPTIME('23:59:59',    '%-H:%M:%S')
        )
    )::TIME)::DECIMAL(10,3)
);
