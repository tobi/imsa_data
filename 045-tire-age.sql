-- Estimate tire age (green-flag laps) for each lap
-- See doc/tires.md for methodology and research
--
-- Race sessions only — practice/qualifying/test are NULL (tires reused constantly).
--
-- Approach: score-and-allocate
--   1. Every pit event (driver change or mid-stint pit) gets a tire-change likelihood score
--   2. Driver changes always consume a tire set
--   3. A per-car tire budget is computed (known allocation or estimated from GF laps)
--   4. Remaining budget after driver changes is allocated to the highest-scored mid-stint pits
--   5. Budget is pro-rated for cars that don't finish (less distance = fewer sets used)

ALTER TABLE laps ADD COLUMN est_tire_age INTEGER;

-- ============================================================
-- Step 1: Mark pit events and GF laps (race only)
-- ============================================================
CREATE TEMP TABLE tire_base AS
SELECT session_id, car, lap, flags, lap_time, stint_lap, stint_start, pit_time,
    session_time,
    CASE
        WHEN stint_start = 1 AND stint_lap = 0 THEN 1
        WHEN pit_time IS NOT NULL AND stint_lap > 0 THEN 1
        ELSE 0
    END AS is_pit_event,
    CASE WHEN flags = 'GF' AND lap_time IS NOT NULL
              AND stint_lap >= 1 AND pit_time IS NULL
         THEN 1 ELSE 0
    END AS is_gf_lap
FROM laps
WHERE session = 'race';

-- ============================================================
-- Step 2: Assign segment IDs
-- ============================================================
CREATE TEMP TABLE tire_segments AS
SELECT *,
    SUM(is_pit_event) OVER (PARTITION BY session_id, car ORDER BY lap) AS segment_id
FROM tire_base;

-- ============================================================
-- Step 3: Rank GF laps within each segment
-- ============================================================
CREATE TEMP TABLE tire_ranked AS
SELECT *,
    CASE WHEN is_gf_lap = 1 THEN
        SUM(is_gf_lap) OVER (PARTITION BY session_id, car, segment_id ORDER BY lap)
    END AS gf_rank
FROM tire_segments;

-- ============================================================
-- Step 4: Per-segment stats with race phase
-- ============================================================
CREATE TEMP TABLE tire_seg_stats AS
WITH race_end AS (
    SELECT session_id, MAX(session_time) AS race_end_time
    FROM tire_base GROUP BY session_id
),
seg_raw AS (
    SELECT ts.session_id, ts.car, ts.segment_id,
        SUM(ts.is_gf_lap)::INTEGER AS gf_laps,
        MAX(CASE WHEN ts.is_pit_event = 1 AND ts.stint_start = 1 THEN 1 ELSE 0 END)::INTEGER AS is_stint_start,
        MIN(ts.session_time) AS seg_start_time,
        re.race_end_time
    FROM tire_segments ts
    JOIN race_end re USING (session_id)
    GROUP BY ts.session_id, ts.car, ts.segment_id, re.race_end_time
)
SELECT *,
    CASE
        WHEN seg_start_time > race_end_time - 7200 THEN 'last_2h'
        WHEN seg_start_time <= race_end_time * 0.5 THEN 'early'
        ELSE 'middle'
    END AS race_phase
FROM seg_raw;

-- ============================================================
-- Step 5: Start/end pace per segment
-- ============================================================
CREATE TEMP TABLE tire_seg_pace AS
SELECT r.session_id, r.car, r.segment_id,
    AVG(CASE WHEN r.gf_rank BETWEEN 2 AND 4 THEN r.lap_time END) AS start_pace,
    AVG(CASE WHEN r.gf_rank > s.gf_laps - 4 AND r.gf_rank <= s.gf_laps THEN r.lap_time END) AS end_pace
FROM tire_ranked r
JOIN tire_seg_stats s USING (session_id, car, segment_id)
WHERE r.is_gf_lap = 1 AND s.gf_laps >= 2
GROUP BY r.session_id, r.car, r.segment_id;

-- ============================================================
-- Step 6: Score each segment for tire-change likelihood
-- ============================================================
CREATE TEMP TABLE tire_scored AS
WITH info AS (
    SELECT s.*, p.start_pace, p.end_pace,
        LAG(p.end_pace) OVER w AS prev_end_pace,
        LAG(s.gf_laps) OVER w AS prev_gf
    FROM tire_seg_stats s
    LEFT JOIN tire_seg_pace p USING (session_id, car, segment_id)
    WINDOW w AS (PARTITION BY s.session_id, s.car ORDER BY s.segment_id)
)
SELECT *,
    CASE
        -- Session start: always gets tires, not scored
        WHEN segment_id <= 1 THEN NULL
        -- Everything else (driver changes AND mid-stint pits) gets scored.
        -- Driver changes get a bonus but still compete for the budget.
        ELSE
            -- Driver change bonus (5 pts): teams almost always change tires at driver swaps
            CASE WHEN is_stint_start = 1 THEN 5.0 ELSE 0.0 END
            -- Pace improvement (0-5 pts): bigger improvement = more likely new tires
            + COALESCE(GREATEST(0, LEAST((prev_end_pace - start_pace) * 1.5, 5)), 0)
            -- Race phase bonus (0-5 pts): later = more likely single-stinting
            + CASE race_phase WHEN 'last_2h' THEN 5.0 WHEN 'middle' THEN 2.0 ELSE 0.0 END
            -- Tire wear (0-3 pts): more GF laps on old set = more reason to change
            + LEAST(COALESCE(prev_gf, 0) / 10.0, 3.0)
            -- Splash penalty: very short runs are almost certainly fuel-only
            + CASE WHEN COALESCE(prev_gf, 0) < 3 THEN -100.0
                   WHEN COALESCE(prev_gf, 0) < 5 THEN -20.0
                   ELSE 0.0
            END
    END AS tire_change_score
FROM info;

-- ============================================================
-- Step 7: Compute per-car tire budget and allocate
-- ============================================================
-- Budget = known allocation (pro-rated for DNFs) or estimated from GF laps.
-- Driver changes always consume a set. Remaining budget goes to the
-- highest-scored mid-stint pits.
CREATE TEMP TABLE tire_classified AS
WITH
-- Known tire allocations: (event, min_year, max_year) → race sets per car
-- Source: IMSA Michelin bulletins. Add more as they become available.
known_alloc(event_name, min_year, max_year, race_sets) AS (VALUES
    ('Sebring', '2025', '2099', 12)
),
car_stats AS (
    SELECT s.session_id, s.car,
        SUM(s.gf_laps) AS total_gf,
        s.race_end_time,
        -- Pull event/year for allocation lookup
        ANY_VALUE(l.event) AS event_name,
        ANY_VALUE(l.year) AS race_year
    FROM tire_seg_stats s
    JOIN laps l ON l.session_id = s.session_id AND l.car = s.car AND l.session = 'race'
    GROUP BY s.session_id, s.car, s.race_end_time
),
leader_gf AS (
    SELECT session_id, MAX(total_gf) AS leader_gf
    FROM car_stats GROUP BY session_id
),
car_budget AS (
    SELECT c.*,
        l.leader_gf,
        -- Pro-rate factor: fraction of full race completed
        CASE WHEN l.leader_gf > 0 THEN LEAST(c.total_gf::FLOAT / l.leader_gf, 1.0) ELSE 1.0 END AS pro_rate,
        -- Use known allocation if available, otherwise estimate (~1 per 25 GF laps)
        COALESCE(
            (SELECT ka.race_sets FROM known_alloc ka
             WHERE c.event_name = ka.event_name
               AND c.race_year >= ka.min_year AND c.race_year <= ka.max_year),
            GREATEST(2, CEIL(c.total_gf / 25.0))
        )::INTEGER AS base_sets
    FROM car_stats c
    JOIN leader_gf l USING (session_id)
),
budget AS (
    SELECT *,
        -- Pro-rate the budget for DNFs (less distance = fewer sets used)
        -- Subtract 1 for the start set; rest is allocated by score ranking
        GREATEST(0,
            GREATEST(1, CEIL(base_sets * pro_rate))::INTEGER - 1
        ) AS pit_stop_budget
    FROM car_budget
),
-- Rank ALL scored pit events (driver changes + mid-stint pits) by score
scored_ranked AS (
    SELECT ts.*,
        ROW_NUMBER() OVER (
            PARTITION BY ts.session_id, ts.car
            ORDER BY ts.tire_change_score DESC NULLS LAST
        ) AS score_rank
    FROM tire_scored ts
    WHERE ts.tire_change_score IS NOT NULL
)
SELECT
    ts.session_id, ts.car, ts.segment_id,
    ts.gf_laps, ts.is_stint_start, ts.tire_change_score,
    CASE
        -- Start: always new
        WHEN ts.segment_id <= 1 THEN TRUE
        -- All other pit events: new tires if within the budget (top N by score)
        WHEN sr.score_rank IS NOT NULL AND sr.score_rank <= b.pit_stop_budget THEN TRUE
        -- Otherwise: same tires
        ELSE FALSE
    END AS is_new_tires
FROM tire_scored ts
LEFT JOIN scored_ranked sr
    ON sr.session_id = ts.session_id AND sr.car = ts.car AND sr.segment_id = ts.segment_id
LEFT JOIN budget b
    ON b.session_id = ts.session_id AND b.car = ts.car;

-- ============================================================
-- Step 8: Assign tire set IDs
-- ============================================================
CREATE TEMP TABLE tire_with_sets AS
SELECT *,
    SUM(CASE WHEN is_new_tires THEN 1 ELSE 0 END) OVER (
        PARTITION BY session_id, car ORDER BY segment_id
    ) AS tire_set_id
FROM tire_classified;

-- ============================================================
-- Step 9: GF lap offset from prior segments in the same tire set
-- ============================================================
CREATE TEMP TABLE tire_offsets AS
SELECT session_id, car, segment_id, tire_set_id, is_new_tires,
    COALESCE(
        SUM(gf_laps) OVER (
            PARTITION BY session_id, car, tire_set_id
            ORDER BY segment_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0
    ) AS gf_offset
FROM tire_with_sets;

-- ============================================================
-- Step 10: Compute per-lap tire age and update
-- ============================================================
UPDATE laps
SET est_tire_age = o.gf_offset + COALESCE(f.gf_before, 0)
FROM tire_offsets o
JOIN (
    SELECT session_id, car, lap, segment_id,
        COALESCE(
            SUM(is_gf_lap) OVER (
                PARTITION BY session_id, car, segment_id
                ORDER BY lap
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0
        ) AS gf_before
    FROM tire_segments
) f USING (session_id, car, segment_id)
WHERE laps.session_id = f.session_id AND laps.car = f.car AND laps.lap = f.lap;

DROP TABLE tire_base;
DROP TABLE tire_segments;
DROP TABLE tire_ranked;
DROP TABLE tire_seg_stats;
DROP TABLE tire_seg_pace;
DROP TABLE tire_scored;
DROP TABLE tire_classified;
DROP TABLE tire_with_sets;
DROP TABLE tire_offsets;

-- Summary
SELECT
    'tire_age' AS metric,
    COUNT(*) FILTER (WHERE est_tire_age IS NOT NULL) AS estimated,
    COUNT(*) FILTER (WHERE est_tire_age = 0) AS age_zero,
    ROUND(AVG(est_tire_age), 1) AS avg_age,
    MAX(est_tire_age) AS max_age
FROM laps WHERE session = 'race';
