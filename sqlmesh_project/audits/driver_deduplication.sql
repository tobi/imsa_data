-- Driver Deduplication Audits for dim_drivers
-- Each audit returns rows that violate the quality rule (0 rows = pass)

-- Audit: Driver IDs should be unique
AUDIT (
    name assert_unique_driver_ids,
    dialect duckdb
);

SELECT driver_id, COUNT(*) AS cnt
FROM @this_model
GROUP BY driver_id
HAVING COUNT(*) > 1;


-- Audit: Display name should be in name_variants
AUDIT (
    name assert_display_name_in_variants,
    dialect duckdb
);

SELECT driver_id, display_name, name_variants
FROM @this_model
WHERE NOT list_contains(name_variants, display_name);


-- Audit: No empty name_variants arrays
AUDIT (
    name assert_non_empty_variants,
    dialect duckdb
);

SELECT driver_id, display_name, name_variants
FROM @this_model
WHERE name_variants IS NULL OR LEN(name_variants) = 0;


-- Audit: No name variant should appear in multiple driver clusters
AUDIT (
    name assert_unique_name_variants,
    dialect duckdb
);

WITH exploded AS (
    SELECT driver_id, UNNEST(name_variants) AS name_variant
    FROM @this_model
)
SELECT name_variant, COUNT(DISTINCT driver_id) AS driver_count,
       ARRAY_AGG(driver_id) AS driver_ids
FROM exploded
GROUP BY name_variant
HAVING COUNT(DISTINCT driver_id) > 1;


-- Audit: Name variants within a cluster should have reasonable similarity
AUDIT (
    name assert_cluster_name_similarity,
    dialect duckdb
);
-- All names in a cluster should have >0.6 Jaro-Winkler similarity
-- This catches false positives where unrelated names got merged

WITH exploded AS (
    SELECT driver_id, display_name, UNNEST(name_variants) AS name_variant
    FROM @this_model
    WHERE variant_count > 1
),
pairs AS (
    SELECT
        a.driver_id,
        a.display_name,
        a.name_variant AS name_a,
        b.name_variant AS name_b,
        jaro_winkler_similarity(LOWER(a.name_variant), LOWER(b.name_variant)) AS similarity
    FROM exploded a
    JOIN exploded b ON a.driver_id = b.driver_id AND a.name_variant < b.name_variant
)
SELECT driver_id, display_name, name_a, name_b, ROUND(similarity, 3) AS similarity
FROM pairs
WHERE similarity < 0.6
ORDER BY similarity;
