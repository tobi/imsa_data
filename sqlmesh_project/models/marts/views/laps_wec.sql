MODEL (
    name marts.laps_wec,
    kind VIEW,
    description 'All WEC laps across all sessions.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series_code = 'wec'
