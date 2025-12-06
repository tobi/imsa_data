MODEL (
    name marts.laps_alms,
    kind VIEW,
    description 'All Asian Le Mans laps across all sessions.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series_code = 'alms'
