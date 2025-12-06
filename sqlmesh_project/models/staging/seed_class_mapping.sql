MODEL (
    name staging.seed_class_mapping,
    kind SEED (
        path '../../seeds/class_mapping.csv'
    ),
    columns (
        series_code VARCHAR,
        class_original VARCHAR,
        class_normalized VARCHAR,
        class_category VARCHAR,
        description VARCHAR
    ),
    grain (series_code, class_original)
);
