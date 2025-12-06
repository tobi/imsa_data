MODEL (
    name marts.laps_wec_2024,
    kind VIEW,
    description 'WEC 2024 race laps only.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series = 'wec-2024' AND session = 'race'
