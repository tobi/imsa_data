MODEL (
    name marts.laps_wec_2025,
    kind VIEW,
    description 'WEC 2025 race laps only.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series = 'wec-2025' AND session = 'race'
