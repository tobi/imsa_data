CREATE OR REPLACE MACRO license_rank(license) AS (
    CASE
        WHEN UPPER(license[1:1]) = 'P' THEN 5 -- Platinum
        WHEN UPPER(license[1:1]) = 'G' THEN 4 -- Gold
        WHEN UPPER(license[1:1]) = 'S' THEN 3 -- Silver
        WHEN UPPER(license[1:1]) = 'B' THEN 2 -- Bronze
        ELSE 0
    END
);

CREATE TEMP TABLE event_drivers_raw AS
    SELECT
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 1) as year,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 2) as event,
        regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 4) as session,

        -- Team and class
        TEAM as team,
        _CLASS as class,

        -- Date
        strptime(regexp_extract(filename, '^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-results\.csv$', 3), '%Y%m%d%H%M') as date,

        -- Drivers list
        list_value(
            struct_pack(
                name :=  CONCAT(DRIVER1_FIRSTNAME, ' ', DRIVER1_SECONDNAME),
                driver_id := DRIVER1_IMSA_DRIVERID,
                country := DRIVER1_COUNTRY,
                license := DRIVER1_LICENSE,
                present := DRIVER1_FIRSTNAME IS NOT NULL AND DRIVER1_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER2_FIRSTNAME, ' ', DRIVER2_SECONDNAME),
                driver_id := DRIVER2_IMSA_DRIVERID,
                country := DRIVER2_COUNTRY,
                license := DRIVER2_LICENSE,
                present := DRIVER2_FIRSTNAME IS NOT NULL AND DRIVER2_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER3_FIRSTNAME, ' ', DRIVER3_SECONDNAME),
                driver_id := DRIVER3_IMSA_DRIVERID,
                country := DRIVER3_COUNTRY,
                license := DRIVER3_LICENSE,
                present := DRIVER3_FIRSTNAME IS NOT NULL AND DRIVER3_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER4_FIRSTNAME, ' ', DRIVER4_SECONDNAME),
                driver_id := DRIVER4_IMSA_DRIVERID,
                country := DRIVER4_COUNTRY,
                license := DRIVER4_LICENSE,
                present := DRIVER4_FIRSTNAME IS NOT NULL AND DRIVER4_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER5_FIRSTNAME, ' ', DRIVER5_SECONDNAME),
                driver_id := DRIVER5_IMSA_DRIVERID,
                country := DRIVER5_COUNTRY,
                license := DRIVER5_LICENSE,
                present := DRIVER5_FIRSTNAME IS NOT NULL AND DRIVER5_SECONDNAME IS NOT NULL
            ),
            struct_pack(
                name :=  CONCAT(DRIVER6_FIRSTNAME, ' ', DRIVER6_SECONDNAME),
                driver_id := DRIVER6_IMSA_DRIVERID,
                country := DRIVER6_COUNTRY,
                license := DRIVER6_LICENSE,
                present := DRIVER6_FIRSTNAME IS NOT NULL AND DRIVER6_SECONDNAME IS NOT NULL
            )
        ) as drivers,

        -- File name
        filename

    FROM read_csv(
        "data/*/*/*results.csv",
        union_by_name=true,
        filename=true,
        null_padding=true,
        normalize_names=true
    );


CREATE OR REPLACE TABLE event_drivers AS
SELECT
    year,
    event,
    session,
    date,
    d.driver_id,
    d.name,
    d.license,
    license_rank(d.license) as license_rank,
    team,
    class,
    d.country
FROM event_drivers_raw
CROSS JOIN UNNEST(drivers) AS u (d)
WHERE d.present;

-- fix some unfortunate data typos
UPDATE event_drivers SET license = 'Platinum', license_rank = license_rank(license) WHERE license = 'Platinium';



CREATE OR REPLACE VIEW drivers AS
SELECT
    name,
    class,
    ANY_VALUE(license) as license,
    MAX(license_rank) as license_rank,
    MAX(date) as last_seen,
    ANY_VALUE(team) as team,
    ANY_VALUE(country) as country,
    ANY_VALUE(year) as year
FROM event_drivers
GROUP BY name, class
ORDER BY license_rank DESC, last_seen DESC;

SELECT COUNT(DISTINCT name) as drivers, COUNT(DISTINCT license) as licenses, COUNT(DISTINCT class) as classes, COUNT(DISTINCT team) as teams, COUNT(DISTINCT country) as countries, COUNT(DISTINCT year) as years FROM event_drivers;