MODEL (
    name marts.laps_imsa_2025,
    kind VIEW,
    description 'IMSA 2025 race laps only.'
);

SELECT * FROM marts.laps_with_bpillar WHERE series = 'imsa-2025' AND session = 'race'
