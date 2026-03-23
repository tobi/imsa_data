-- Estimate tire age (green-flag laps) for each lap
-- See doc/tires.md for methodology and research
--
-- Race sessions:
--   - Driver changes (stint boundaries): always assume new tires
--   - Same-driver pit stops: compare pace before/after
--     If driver got measurably faster → new tires
--     If pace similar or slower → same tires (fuel-only stop)
--   - Tire age counts only green-flag racing laps (excludes outlaps, pit laps, FCY)
--
-- Non-race sessions (practice, qualifying, warmup, test):
--   est_tire_age = NULL. Teams reuse tires constantly across driver changes
--   and pit stops in practice — the true tire age is unknowable from timing
--   data alone. Typical allocation is ~6 sets for all practice sessions.
--   Future enhancement: detect qualifying simulations in practice (short stint,
--   slow outlap, peak among driver's event-best) and mark those as fresh tires.

ALTER TABLE laps ADD COLUMN est_tire_age INTEGER;

-- Step 1: Mark pit events and GF laps (race sessions only)
CREATE TEMP TABLE tire_base AS
SELECT session_id, car, lap, flags, lap_time, stint_lap, stint_start, pit_time,
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

-- Step 2: Assign segment IDs (each pit event starts a new segment)
CREATE TEMP TABLE tire_segments AS
SELECT *,
    SUM(is_pit_event) OVER (PARTITION BY session_id, car ORDER BY lap) AS segment_id
FROM tire_base;

-- Step 3: Rank GF laps within each segment (for pace calculation)
CREATE TEMP TABLE tire_ranked AS
SELECT *,
    CASE WHEN is_gf_lap = 1 THEN
        SUM(is_gf_lap) OVER (PARTITION BY session_id, car, segment_id ORDER BY lap)
    END AS gf_rank
FROM tire_segments;

-- Step 4: Per-segment totals and flags
CREATE TEMP TABLE tire_seg_stats AS
SELECT session_id, car, segment_id,
    SUM(is_gf_lap)::INTEGER AS gf_laps,
    MAX(CASE WHEN is_pit_event = 1 AND stint_start = 1 THEN 1 ELSE 0 END)::INTEGER AS is_stint_start
FROM tire_segments
GROUP BY session_id, car, segment_id;

-- Step 5: Start/end pace per segment (skip warmup lap for start pace)
CREATE TEMP TABLE tire_seg_pace AS
SELECT r.session_id, r.car, r.segment_id,
    AVG(CASE WHEN r.gf_rank BETWEEN 2 AND 4 THEN r.lap_time END) AS start_pace,
    AVG(CASE WHEN r.gf_rank > s.gf_laps - 4 AND r.gf_rank <= s.gf_laps THEN r.lap_time END) AS end_pace
FROM tire_ranked r
JOIN tire_seg_stats s USING (session_id, car, segment_id)
WHERE r.is_gf_lap = 1 AND s.gf_laps >= 2
GROUP BY r.session_id, r.car, r.segment_id;

-- Step 6: Classify each segment — new tires or same tires?
CREATE TEMP TABLE tire_classified AS
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
        WHEN segment_id <= 1 THEN TRUE                              -- session start
        WHEN is_stint_start = 1 THEN TRUE                           -- driver change
        WHEN start_pace IS NOT NULL AND prev_end_pace IS NOT NULL
             AND start_pace < prev_end_pace - 0.3 THEN TRUE         -- got faster after pit
        WHEN prev_gf < 3 THEN FALSE                                 -- splash under yellow
        WHEN prev_gf >= 25
             AND (start_pace IS NULL OR prev_end_pace IS NULL)
        THEN TRUE                                                    -- long run, no pace data
        ELSE FALSE                                                   -- default: same tires
    END AS is_new_tires
FROM info;

-- Step 7: Assign tire set IDs
CREATE TEMP TABLE tire_with_sets AS
SELECT *,
    SUM(CASE WHEN is_new_tires THEN 1 ELSE 0 END) OVER (
        PARTITION BY session_id, car ORDER BY segment_id
    ) AS tire_set_id
FROM tire_classified;

-- Step 8: GF lap offset from prior segments in the same tire set
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

-- Step 9: Compute per-lap tire age and update (race laps only)
-- tire_age = gf_offset (prior segments in same tire set) + GF laps before this lap in segment
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
