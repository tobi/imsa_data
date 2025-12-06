MODEL (
    name marts.laps_imsa,
    kind VIEW,
    description 'All IMSA laps across all sessions.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series_code = 'imsa'
