-- Convenience views for season-specific analysis.
-- Update this file when new seasons are added to the dataset.

CREATE OR REPLACE VIEW laps_2021 AS
SELECT *
FROM laps
WHERE year = '2021';

CREATE OR REPLACE VIEW laps_2022 AS
SELECT *
FROM laps
WHERE year = '2022';

CREATE OR REPLACE VIEW laps_2023 AS
SELECT *
FROM laps
WHERE year = '2023';

CREATE OR REPLACE VIEW laps_2024 AS
SELECT *
FROM laps
WHERE year = '2024';

CREATE OR REPLACE VIEW laps_2025 AS
SELECT *
FROM laps
WHERE year = '2025';
