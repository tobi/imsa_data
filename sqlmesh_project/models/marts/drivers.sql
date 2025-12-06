MODEL (
    name marts.drivers,
    kind FULL,
    cron '@daily',
    grain (driver_id),
    description 'Driver table with globally unique driver IDs, clustering name variants via fuzzy matching and IMSA IDs.',
    audits (
        assert_unique_driver_ids,
        assert_display_name_in_variants,
        assert_non_empty_variants,
        assert_unique_name_variants,
        assert_cluster_name_similarity
    )
);

-- Step 1: Get unique canonical names (aggregate across series for global matching)
WITH driver_names_by_series AS (
    SELECT
        canonical_name,
        series_code,
        name_normalized,
        imsa_driver_id,
        country,
        total_appearances
    FROM staging.stg_driver_names
),

-- Aggregate to get unique names across all series
driver_names AS (
    SELECT
        canonical_name,
        name_normalized,
        MODE(country) FILTER (WHERE country IS NOT NULL) AS country,
        SUM(total_appearances) AS total_appearances
    FROM driver_names_by_series
    GROUP BY canonical_name, name_normalized
),

-- Step 2: Find IMSA ID matches ONLY within the same series
-- AND only if names have some baseline similarity (>0.7) to avoid bad ID data
imsa_id_matches AS (
    SELECT DISTINCT
        LEAST(a.canonical_name, b.canonical_name) AS name_a,
        GREATEST(a.canonical_name, b.canonical_name) AS name_b
    FROM driver_names_by_series a
    JOIN driver_names_by_series b
        ON a.series_code = b.series_code  -- Same series only!
        AND a.imsa_driver_id = b.imsa_driver_id
        AND a.imsa_driver_id IS NOT NULL
        AND a.canonical_name < b.canonical_name
    -- Must also pass a basic name similarity check to catch bad ID data
    WHERE jaro_winkler_similarity(a.name_normalized, b.name_normalized) > 0.7
),

-- Step 3: Find fuzzy name matches (across all series)
-- Using high Jaro-Winkler similarity or name containment
fuzzy_matches AS (
    SELECT DISTINCT
        LEAST(a.canonical_name, b.canonical_name) AS name_a,
        GREATEST(a.canonical_name, b.canonical_name) AS name_b
    FROM driver_names a
    CROSS JOIN driver_names b
    WHERE a.canonical_name < b.canonical_name
      AND (
          -- Very high similarity on normalized names (>0.95) for any length
          jaro_winkler_similarity(a.name_normalized, b.name_normalized) > 0.95
          -- High similarity (>0.92) but only for longer names to avoid false positives
          OR (jaro_winkler_similarity(a.name_normalized, b.name_normalized) > 0.92
              AND LENGTH(a.name_normalized) >= 15
              AND LENGTH(b.name_normalized) >= 15)
          -- One name contains the other as a prefix (e.g., "Alex Riberas" vs "Alex Riberas Bou")
          OR (LENGTH(a.name_normalized) >= 12
              AND LENGTH(b.name_normalized) >= 12
              AND (a.name_normalized LIKE b.name_normalized || ' %'
                   OR b.name_normalized LIKE a.name_normalized || ' %'))
      )
),

-- Combine all matching pairs
matching_pairs AS (
    SELECT name_a, name_b FROM imsa_id_matches
    UNION
    SELECT name_a, name_b FROM fuzzy_matches
),

-- Step 3: Build adjacency list - for each name, find all its matches
adjacency AS (
    SELECT name_a AS name, name_b AS connected_name FROM matching_pairs
    UNION ALL
    SELECT name_b AS name, name_a AS connected_name FROM matching_pairs
    UNION ALL
    SELECT canonical_name AS name, canonical_name AS connected_name FROM driver_names
),

-- Step 4: Find the minimum name in each connected component (cluster root)
-- Iterate to propagate transitive connections
pass_1 AS (
    SELECT name, MIN(connected_name) AS cluster_root
    FROM adjacency
    GROUP BY name
),

pass_2 AS (
    SELECT p1.name, MIN(p2.cluster_root) AS cluster_root
    FROM pass_1 p1
    JOIN pass_1 p2 ON p1.cluster_root = p2.name
    GROUP BY p1.name
),

pass_3 AS (
    SELECT p1.name, MIN(p2.cluster_root) AS cluster_root
    FROM pass_2 p1
    JOIN pass_2 p2 ON p1.cluster_root = p2.name
    GROUP BY p1.name
),

pass_4 AS (
    SELECT p1.name, MIN(p2.cluster_root) AS cluster_root
    FROM pass_3 p1
    JOIN pass_3 p2 ON p1.cluster_root = p2.name
    GROUP BY p1.name
),

-- Step 5: Join clusters back to driver metadata
clustered AS (
    SELECT
        p.name AS canonical_name,
        p.cluster_root,
        d.name_normalized,
        d.country,
        d.total_appearances
    FROM pass_4 p
    JOIN driver_names d ON p.name = d.canonical_name
),

-- Get IMSA IDs separately from series-level data
clustered_imsa_ids AS (
    SELECT DISTINCT
        p.cluster_root,
        ds.imsa_driver_id
    FROM pass_4 p
    JOIN driver_names_by_series ds ON p.name = ds.canonical_name
    WHERE ds.imsa_driver_id IS NOT NULL
),

-- Step 6: Aggregate each cluster
cluster_aggregates AS (
    SELECT
        c.cluster_root,
        -- Pick name with most appearances as display name
        FIRST(c.canonical_name ORDER BY c.total_appearances DESC, LENGTH(c.canonical_name) DESC) AS display_name,
        -- Collect all name variants
        ARRAY_AGG(DISTINCT c.canonical_name ORDER BY c.canonical_name) AS name_variants,
        -- Use most common IMSA ID from series-level data
        (SELECT MODE(imsa_driver_id) FROM clustered_imsa_ids ci WHERE ci.cluster_root = c.cluster_root) AS imsa_driver_id,
        -- Use most common country
        MODE(c.country) FILTER (WHERE c.country IS NOT NULL) AS country,
        -- Sum total appearances
        SUM(c.total_appearances) AS total_appearances,
        -- Count variants
        COUNT(DISTINCT c.canonical_name) AS variant_count
    FROM clustered c
    GROUP BY c.cluster_root
)

SELECT
    -- Generate stable driver ID from cluster root
    'drv_' || SUBSTRING(MD5(cluster_root), 1, 8) AS driver_id,
    display_name,
    name_variants,
    imsa_driver_id,
    country,
    total_appearances,
    variant_count
FROM cluster_aggregates
ORDER BY display_name
