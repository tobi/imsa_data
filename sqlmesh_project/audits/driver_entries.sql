-- Driver Entries Audits for fact_driver_entries
-- Each audit returns rows that violate the quality rule (0 rows = pass)

-- Audit: Entry IDs should be unique
AUDIT (
    name assert_unique_entry_ids,
    dialect duckdb
);

SELECT entry_id, COUNT(*) AS cnt
FROM @this_model
GROUP BY entry_id
HAVING COUNT(*) > 1;


-- Audit: All driver_ids should reference valid dim_drivers
AUDIT (
    name assert_valid_driver_references,
    dialect duckdb
);

SELECT DISTINCT f.driver_id, f.driver_display_name
FROM @this_model f
LEFT JOIN marts.dim_drivers d ON f.driver_id = d.driver_id
WHERE d.driver_id IS NULL;
