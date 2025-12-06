MODEL (
    name marts.drivers,
    kind FULL,
    cron '@daily',
    grain (driver_id),
    description 'Driver snapshot table with latest known driver information across all sessions.'
);

WITH ranked AS (
    SELECT
        driver_id,
        canonical_name,
        name,
        imsa_driver_id,
        license,
        license_rank,
        team,
        country,
        class,
        year,
        car,
        start_date,
        ROW_NUMBER() OVER (
            PARTITION BY driver_id
            ORDER BY start_date DESC
        ) AS row_num
    FROM staging.stg_event_drivers
)

SELECT
    driver_id,
    canonical_name,
    name AS preferred_name,
    imsa_driver_id,
    license,
    license_rank,
    country,
    team,
    class AS last_class,
    year AS last_year,
    car AS last_car,
    start_date AS last_seen
FROM ranked
WHERE row_num = 1
