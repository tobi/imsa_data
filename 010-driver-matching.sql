-- Automated Driver Matching
-- Identifies duplicate driver records and generates alias mappings

---------------------------------------------------------------------
-- 1. CANDIDATE PAIRS (fuzzy name match, never raced together)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_match_candidates AS
WITH base_pairs AS (
    SELECT 
        a.driver_id as id1, 
        b.driver_id as id2,
        a.canonical_name as name1,
        b.canonical_name as name2,
        jaro_winkler_similarity(a.driver_id, b.driver_id) as name_similarity,
        levenshtein(a.driver_id, b.driver_id) as edit_distance,
        a.total_events as events1,
        b.total_events as events2,
        a.total_laps as laps1,
        b.total_laps as laps2,
        a.country as country1,
        b.country as country2,
        a.series_list as series1,
        b.series_list as series2
    FROM drivers_v a, drivers_v b
    WHERE a.driver_id < b.driver_id
      AND jaro_winkler_similarity(a.driver_id, b.driver_id) > 0.82
),
with_race_overlap AS (
    SELECT 
        bp.*,
        (SELECT COUNT(*) FROM event_driver_summary e1, event_driver_summary e2 
         WHERE e1.driver_id = bp.id1 AND e2.driver_id = bp.id2
         AND e1.series_code = e2.series_code AND e1.year = e2.year AND e1.event = e2.event
        ) as races_together
    FROM base_pairs bp
),
with_context AS (
    SELECT 
        wo.*,
        -- Shared teams (strong signal)
        (SELECT COUNT(DISTINCT e1.team) FROM event_driver_summary e1, event_driver_summary e2
         WHERE e1.driver_id = wo.id1 AND e2.driver_id = wo.id2 AND e1.team = e2.team
        ) as shared_teams,
        -- Shared car+team combinations (very strong signal)
        (SELECT COUNT(*) FROM event_driver_summary e1, event_driver_summary e2
         WHERE e1.driver_id = wo.id1 AND e2.driver_id = wo.id2 
         AND e1.car = e2.car AND e1.team = e2.team
        ) as shared_car_team,
        -- Same country
        CASE WHEN wo.country1 = wo.country2 AND wo.country1 IS NOT NULL THEN 1 ELSE 0 END as same_country
    FROM with_race_overlap wo
)
SELECT * FROM with_context;

---------------------------------------------------------------------
-- 2. MATCHING RULES & CONFIDENCE SCORING
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_match_scores AS
SELECT 
    id1, id2, name1, name2,
    name_similarity,
    edit_distance,
    events1, events2,
    laps1, laps2,
    races_together,
    shared_teams,
    shared_car_team,
    same_country,
    
    -- Definitive: raced together = different people
    CASE WHEN races_together > 0 THEN 'DIFFERENT' ELSE 'CANDIDATE' END as status,
    
    -- Surname similarity check
    jaro_winkler_similarity(
        string_split(id1, ' ')[array_length(string_split(id1, ' '))],
        string_split(id2, ' ')[array_length(string_split(id2, ' '))]
    ) as surname_similarity,
    
    -- Confidence score (0-100)
    CASE 
        WHEN races_together > 0 THEN 0  -- Definitely different
        -- Different surnames = likely different people (unless very high context match)
        WHEN jaro_winkler_similarity(
                string_split(id1, ' ')[array_length(string_split(id1, ' '))],
                string_split(id2, ' ')[array_length(string_split(id2, ' '))]
             ) < 0.8 AND shared_car_team < 50 THEN 10  -- Low confidence
        ELSE LEAST(100, 
            -- Base score from name similarity
            (name_similarity - 0.82) * 200 +  -- 0-36 points
            -- Bonus for identical surname
            CASE WHEN jaro_winkler_similarity(
                    string_split(id1, ' ')[array_length(string_split(id1, ' '))],
                    string_split(id2, ' ')[array_length(string_split(id2, ' '))]
                 ) > 0.95 THEN 20 ELSE 0 END +
            -- Bonus for shared context
            CASE WHEN shared_car_team > 20 THEN 30
                 WHEN shared_car_team > 5 THEN 20
                 WHEN shared_car_team > 0 THEN 10 ELSE 0 END +
            CASE WHEN shared_teams > 1 THEN 15 
                 WHEN shared_teams > 0 THEN 8 ELSE 0 END +
            -- Bonus for same country
            same_country * 5 +
            -- Penalty for Jr/Sr patterns (potential father/son)
            CASE WHEN id1 LIKE '% jr%' OR id2 LIKE '% jr%' 
                   OR id1 LIKE '% sr%' OR id2 LIKE '% sr%' THEN -20 ELSE 0 END +
            -- Bonus for accent/umlaut differences (common data issue)
            CASE WHEN regexp_replace(id1, '[àáâãäåæçèéêëìíîïñòóôõöøùúûüý]', '', 'g') = 
                      regexp_replace(id2, '[àáâãäåæçèéêëìíîïñòóôõöøùúûüý]', '', 'g') THEN 25 
                 ELSE 0 END
        )
    END as confidence,
    
    -- Reason for match
    CASE 
        WHEN races_together > 0 THEN 'Raced together ' || races_together || ' times'
        WHEN shared_car_team > 20 THEN 'Same car+team ' || shared_car_team || 'x'
        WHEN name_similarity > 0.97 THEN 'Near-identical name'
        WHEN shared_teams > 0 AND name_similarity > 0.93 THEN 'Similar name + shared team'
        WHEN edit_distance <= 2 THEN 'Minor spelling variation'
        ELSE 'Fuzzy name match'
    END as match_reason

FROM driver_match_candidates;

---------------------------------------------------------------------
-- 3. AUTO-MERGE CANDIDATES (high confidence)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_auto_merge AS
SELECT 
    -- Keep the one with more laps as canonical
    CASE WHEN laps1 >= laps2 THEN id1 ELSE id2 END as canonical_id,
    CASE WHEN laps1 >= laps2 THEN id2 ELSE id1 END as alias_id,
    CASE WHEN laps1 >= laps2 THEN name1 ELSE name2 END as canonical_name,
    CASE WHEN laps1 >= laps2 THEN name2 ELSE name1 END as alias_name,
    confidence,
    match_reason,
    events1 + events2 as combined_events,
    laps1 + laps2 as combined_laps
FROM driver_match_scores
WHERE status = 'CANDIDATE' 
  AND confidence >= 70
ORDER BY confidence DESC, combined_laps DESC;

---------------------------------------------------------------------
-- 4. MANUAL REVIEW CANDIDATES (medium confidence)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_review_candidates AS
SELECT 
    id1, id2, name1, name2,
    confidence,
    match_reason,
    events1, events2,
    laps1, laps2,
    shared_teams,
    shared_car_team,
    same_country
FROM driver_match_scores
WHERE status = 'CANDIDATE' 
  AND confidence >= 40 
  AND confidence < 70
ORDER BY confidence DESC;

---------------------------------------------------------------------
-- 5. CONFIRMED DIFFERENT (raced together)
---------------------------------------------------------------------

CREATE OR REPLACE VIEW driver_confirmed_different AS
SELECT 
    id1, id2, name1, name2,
    races_together,
    name_similarity
FROM driver_match_scores
WHERE status = 'DIFFERENT'
ORDER BY name_similarity DESC;

---------------------------------------------------------------------
-- 6. SUMMARY STATS
---------------------------------------------------------------------

-- SELECT 'Auto-merge (confidence >= 70)' as category, COUNT(*) as pairs FROM driver_auto_merge
-- UNION ALL
-- SELECT 'Review (40-70)', COUNT(*) FROM driver_review_candidates
-- UNION ALL  
-- SELECT 'Confirmed different', COUNT(*) FROM driver_confirmed_different;
