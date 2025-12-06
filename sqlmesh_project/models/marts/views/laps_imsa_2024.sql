MODEL (
    name marts.laps_imsa_2024,
    kind VIEW,
    description 'IMSA 2024 race laps only.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series = 'imsa-2024' AND session = 'race'
