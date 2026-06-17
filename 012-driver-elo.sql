-- Driver skill ratings computed lap-by-lap with OpenSkill (Plackett-Luce).
-- Two pools per class (both computed by compute_skill.py):
--   * OVERALL  (license-seeded, full-field): skill_mu/skill_sigma/ordinal,
--              plus the readable elo_before/elo_after/delta mapping.
--   * PEER     (within-license tier): peer_mu/peer_sigma/peer_ordinal -- "how
--              good are you FOR your license class".
-- Confidence: ordinal = mu - 3*sigma (conservative rating).
-- First event still includes the full base in delta, so SUM(delta) = elo.

DROP TABLE IF EXISTS driver_elo;
CREATE TABLE driver_elo AS
SELECT * FROM 'output/driver_elo.csv';

-- Convenience view for current standings by class.
-- Carries both the overall and within-tier conservative ratings, plus the
-- latest sigma so the dashboard can draw confidence bands.
CREATE OR REPLACE VIEW driver_elo_current AS
WITH ranked AS (
  SELECT
    driver_id,
    driver_name,
    class,
    license,
    skill_mu,
    skill_sigma,
    ordinal,
    peer_mu,
    peer_sigma,
    peer_ordinal,
    elo_after,
    session_date,
    ROW_NUMBER() OVER (
      PARTITION BY driver_id, class
      ORDER BY session_date DESC
    ) AS rn
  FROM driver_elo
)
SELECT
  e.driver_id,
  e.driver_name,
  e.class,
  r.elo_after                 AS elo,   -- exact final rating (no rounding drift)
  r.skill_mu,
  r.skill_sigma,
  r.ordinal,                              -- overall conservative rating
  r.peer_mu,
  r.peer_sigma,
  r.peer_ordinal,                         -- within-tier conservative rating
  SUM(e.laps)                 AS total_laps,
  MAX(e.cumulative_laps)      AS cumulative_laps,
  COUNT(*)                    AS events,
  MIN(e.session_date)         AS first_event,
  MAX(e.session_date)         AS last_event,
  MAX(e.license)              AS license
FROM driver_elo e
JOIN ranked r
  ON r.driver_id = e.driver_id
 AND r.class = e.class
 AND r.rn = 1
GROUP BY
  e.driver_id, e.driver_name, e.class,
  r.elo_after,
  r.skill_mu, r.skill_sigma, r.ordinal,
  r.peer_mu, r.peer_sigma, r.peer_ordinal
ORDER BY e.class, r.ordinal DESC;

-- Within-license leaderboard: rank drivers against same-tier peers.
CREATE OR REPLACE VIEW driver_peer_current AS
SELECT
  class,
  license,
  driver_id,
  driver_name,
  peer_ordinal,
  peer_mu,
  peer_sigma,
  cumulative_laps,
  RANK() OVER (
    PARTITION BY class, license
    ORDER BY peer_ordinal DESC
  ) AS peer_rank
FROM driver_elo_current
WHERE license IS NOT NULL AND license <> ''
ORDER BY class, license, peer_ordinal DESC;
