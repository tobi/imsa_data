MODEL (
    name marts.laps_elms,
    kind VIEW,
    description 'All ELMS laps across all sessions.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series_code = 'elms'
