MODEL (
    name staging.stg_driver_names,
    kind FULL,
    cron '@daily',
    grain (canonical_name, series_code),
    description 'Unique driver name variants with normalization for clustering, per series.'
);

-- Collect all unique driver names with their metadata per series
WITH raw_names AS (
    SELECT DISTINCT
        canonical_name,
        series_code,
        imsa_driver_id,
        country,
        @normalize_driver_name(canonical_name) AS name_normalized,
        COUNT(*) OVER (PARTITION BY canonical_name, series_code) AS appearance_count
    FROM staging.stg_event_drivers
    WHERE canonical_name IS NOT NULL
      AND TRIM(canonical_name) != ''
),

-- Deduplicate to get unique name variants per series
unique_names AS (
    SELECT
        canonical_name,
        series_code,
        name_normalized,
        -- Prefer IMSA ID that appears most often with this name in this series
        MODE(imsa_driver_id) AS imsa_driver_id,
        MODE(country) AS country,
        SUM(appearance_count) AS total_appearances
    FROM raw_names
    GROUP BY canonical_name, series_code, name_normalized
)

SELECT
    canonical_name,
    series_code,
    name_normalized,
    imsa_driver_id,
    country,
    total_appearances,
    -- Create a sortable key for consistent ordering
    @driver_name_key(canonical_name) AS sort_key
FROM unique_names
ORDER BY sort_key
