MODEL (
    name marts.laps_with_metadata,
    kind VIEW,
    description 'Laps joined with event metadata for comprehensive analysis.'
);

SELECT
    l.*,
    em.circuit_name,
    em.circuit_country,
    em.race_duration_minutes,
    em.race_distance_km,
    em.event_type,
    em.round_number,
    em.notes as event_notes
FROM marts.laps_with_bpillar l
LEFT JOIN marts.event_metadata em
    ON em.series_code = l.series_code
    AND em.year = l.year
    AND em.event = l.event
