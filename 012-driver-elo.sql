-- Driver Elo ratings computed from lap-by-lap comparisons
-- Each class has independent ratings
-- First event includes +1500 in delta, so SUM(delta) = current Elo

DROP TABLE IF EXISTS driver_elo;
CREATE TABLE driver_elo AS 
SELECT * FROM 'output/driver_elo.csv';

-- Convenience view for current Elo standings by class
CREATE OR REPLACE VIEW driver_elo_current AS
SELECT 
  driver_id,
  driver_name,
  class,
  SUM(delta) as elo,
  SUM(laps) as total_laps,
  MAX(cumulative_laps) as cumulative_laps,
  COUNT(*) as events,
  MIN(session_date) as first_event,
  MAX(session_date) as last_event,
  MAX(license) as license
FROM driver_elo
GROUP BY driver_id, driver_name, class
ORDER BY class, elo DESC;
