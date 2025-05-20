# IMSA Data

This repository collects WeatherTech Championship event data from the IMSA results site and turns it into a DuckDB database.

## Data layout

Downloaded CSV files live in the `data/` directory under their respective year and event folder (for example `data/2024/01-roar-before-the-24/`). Each event folder contains three CSV files per session:

- `*-results.csv`
- `*-laps.csv`
- `*-weather.csv`

## Setup

You will need Ruby (see `mise.toml` for the version) and the DuckDB CLI. Install the required gem and dependencies:

```bash
bundle install
```

## Importing new data

Use the provided script to fetch event data:

```bash
ruby import.rb --year 2024
```

or simply run

```bash
rake import
```

which downloads data for the current season.

## Building the database

After downloading data you can create the DuckDB database and export summary CSV files with:

```bash
rake db:update
```

The resulting database is written to `output/imsa.duckdb` along with `output/drivers.csv` and `output/laps.csv`.

To open the database in an interactive shell run:

```bash
rake db:open
```

## Files

- `import.rb` – downloads IMSA CSV files.
- `all-event-drivers.sql` and `all-event-laps.sql` – DuckDB scripts used to create the database.
- `Rakefile` – tasks to regenerate or open the database and to run the importer.

