MODEL (
    name marts.laps_normalized,
    kind VIEW,
    description 'Laps view with standardized class names for cross-series comparison.'
);

SELECT
    l.*,
    COALESCE(l.class_normalized, l.class) as class_std,
    COALESCE(l.class_category, 'Unknown') as category_std
FROM marts.laps_with_bpillar l
