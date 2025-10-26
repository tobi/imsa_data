-- Class Normalization for Cross-Series Analysis
-- Maps different class names used across series to standardized categories
-- This enables comparison of equivalent classes across IMSA, WEC, ELMS, and Asian Le Mans

-- Create class mapping table
CREATE OR REPLACE TABLE class_mapping (
    series_code VARCHAR,
    class_original VARCHAR,
    class_normalized VARCHAR,
    class_category VARCHAR,
    description VARCHAR,
    PRIMARY KEY (series_code, class_original)
);

-- IMSA WeatherTech Classes
INSERT INTO class_mapping VALUES
    ('imsa', 'GTP', 'LMP1', 'LMP1', 'Grand Touring Prototype - Top IMSA prototype class (LMDh)'),
    ('imsa', 'LMP2', 'LMP2', 'LMP2', 'Le Mans Prototype 2 - International spec'),
    ('imsa', 'LMP3', 'LMP3', 'LMP3', 'Le Mans Prototype 3 - Entry level prototype'),
    ('imsa', 'GTD PRO', 'GT3 Pro', 'GT3', 'GT Daytona Pro - Professional GT3 cars'),
    ('imsa', 'GTD', 'GT3 Am', 'GT3', 'GT Daytona - Pro-Am GT3 cars'),
    ('imsa', 'DPi', 'LMP1', 'LMP1', 'Daytona Prototype international (pre-2023)'),
    ('imsa', 'GTLM', 'GTE', 'GTE', 'GT Le Mans (pre-2022)');

-- WEC (World Endurance Championship) Classes
INSERT INTO class_mapping VALUES
    ('wec', 'HYPERCAR', 'LMP1', 'LMP1', 'LMH/LMDh Hypercar - Top WEC prototype class'),
    ('wec', 'LMP2', 'LMP2', 'LMP2', 'Le Mans Prototype 2'),
    ('wec', 'LMGT3', 'GT3', 'GT3', 'Le Mans GT3'),
    ('wec', 'GTE PRO', 'GTE Pro', 'GTE', 'GTE Professional (pre-2023)'),
    ('wec', 'GTE AM', 'GTE Am', 'GTE', 'GTE Amateur (pre-2023)'),
    ('wec', 'LMP1', 'LMP1', 'LMP1', 'Le Mans Prototype 1 (pre-2021)');

-- ELMS (European Le Mans Series) Classes
INSERT INTO class_mapping VALUES
    ('elms', 'LMP2', 'LMP2', 'LMP2', 'Le Mans Prototype 2'),
    ('elms', 'LMP2 PRO/AM', 'LMP2', 'LMP2', 'Le Mans Prototype 2 Pro-Am'),
    ('elms', 'LMP3', 'LMP3', 'LMP3', 'Le Mans Prototype 3'),
    ('elms', 'LMGT3', 'GT3', 'GT3', 'Le Mans GT3');

-- Asian Le Mans Series Classes
INSERT INTO class_mapping VALUES
    ('alms', 'LMP2', 'LMP2', 'LMP2', 'Le Mans Prototype 2'),
    ('alms', 'LMP2 AM', 'LMP2', 'LMP2', 'Le Mans Prototype 2 Amateur'),
    ('alms', 'LMP3', 'LMP3', 'LMP3', 'Le Mans Prototype 3'),
    ('alms', 'GT', 'GT3', 'GT3', 'GT class'),
    ('alms', 'GT3', 'GT3', 'GT3', 'GT3 class');

-- Le Mans Cup Classes
INSERT INTO class_mapping VALUES
    ('lmc', 'LMP3', 'LMP3', 'LMP3', 'Le Mans Prototype 3'),
    ('lmc', 'GT3', 'GT3', 'GT3', 'GT3 class');

-- Add normalized class field to laps table
ALTER TABLE laps ADD COLUMN IF NOT EXISTS class_normalized VARCHAR;
ALTER TABLE laps ADD COLUMN IF NOT EXISTS class_category VARCHAR;

-- Update laps table with normalized classes
UPDATE laps
SET
    class_normalized = cm.class_normalized,
    class_category = cm.class_category
FROM class_mapping cm
WHERE laps.series_code = cm.series_code
  AND UPPER(TRIM(laps.class)) = UPPER(TRIM(cm.class_original));

-- Create view for cross-series class analysis
CREATE OR REPLACE VIEW laps_normalized AS
SELECT
    l.*,
    COALESCE(l.class_normalized, l.class) as class_std,
    COALESCE(l.class_category, 'Unknown') as category_std
FROM laps l;

-- Summary of class mapping
SELECT
    series_code,
    COUNT(DISTINCT class_original) as original_classes,
    COUNT(DISTINCT class_normalized) as normalized_classes,
    COUNT(DISTINCT class_category) as categories,
    STRING_AGG(DISTINCT class_original, ', ' ORDER BY class_original) as classes
FROM class_mapping
GROUP BY series_code
ORDER BY series_code;

-- Show class distribution across series
.rows
SELECT
    series_code,
    class_category,
    class_normalized,
    STRING_AGG(DISTINCT class_original, ', ' ORDER BY class_original) as original_names,
    COUNT(*) as mappings
FROM class_mapping
GROUP BY series_code, class_category, class_normalized
ORDER BY series_code,
    CASE class_category
        WHEN 'LMP1' THEN 1
        WHEN 'LMP2' THEN 2
        WHEN 'LMP3' THEN 3
        WHEN 'GTE' THEN 4
        WHEN 'GT3' THEN 5
        ELSE 6
    END;
