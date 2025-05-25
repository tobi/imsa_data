# IMSA Data Scraper

A simplified Ruby tool that collects IMSA WeatherTech Championship event data from the official results website and converts it into a DuckDB database for analysis.

## Features

- **Simple**: No external dependencies - uses only Ruby standard library
- **Organized**: Clean object-oriented design with proper error handling
- **Flexible**: Configurable year, output path, and series pattern
- **Robust**: Handles network errors and missing files gracefully

## Data Structure

Downloaded CSV files are organized in the `data/` directory:

```
data/
├── 2024/
│   ├── 01-roar-before-the-24/
│   │   ├── 202401260800_race-results.csv
│   │   ├── 202401260800_race-laps.csv
│   │   └── 202401260800_race-weather.csv
│   └── 02-twelve-hours-of-sebring/
│       └── ...
└── 2023/
    └── ...
```

Each event contains three types of CSV files per session:
- **results**: Race finishing positions and times
- **laps**: Individual lap times and data
- **weather**: Weather conditions during the session

## Setup

You only need Ruby (3.0+) and the DuckDB CLI. No external gems required!

```bash
# Install DuckDB (if not already installed)
# On macOS: brew install duckdb
# On Ubuntu: apt install duckdb

# Clone and use
git clone <repository>
cd imsa-data
```

## Usage

### Import Data

Import data for the current year:
```bash
ruby import.rb
# or
rake import
```

Import data for a specific year:
```bash
ruby import.rb --year 2023
```

Import data for multiple recent years:
```bash
rake import_recent  # imports last 3 years
```

### Build Database

After importing data, create the DuckDB database:
```bash
rake db:update
```

This creates:
- `output/imsa.duckdb` - The main database
- `output/drivers.csv` - Driver summary data
- `output/laps.csv` - Lap summary data

### Explore Data

Open the database in interactive mode:
```bash
rake db:open
```

### Clean Up

Remove generated files:
```bash
rake clean
```

## Command Line Options

The import script supports several options:

```bash
ruby import.rb [options]
  -y, --year YEAR              Year to fetch (default: current year)
  -o, --output-path PATH        Output directory (default: data/)
  -s, --series-pattern PATTERN  Series pattern (default: IMSA WeatherTech)
  -h, --help                   Show help message
```

## Files

- **`import.rb`** - Main scraper with clean object-oriented design
- **`Rakefile`** - Build tasks for database generation and data import
- **`all-event-drivers.sql`** - DuckDB script for driver data aggregation
- **`all-event-laps.sql`** - DuckDB script for lap data aggregation

## Architecture

The code is organized into a simple `IMSAImporter` class that:

1. **Discovers events** - Finds all events for a given year
2. **Filters series** - Looks for IMSA WeatherTech events
3. **Downloads CSVs** - Gets results, laps, and weather data
4. **Converts format** - Transforms semicolon-separated to comma-separated CSV
5. **Organizes files** - Saves in a clean directory structure

The design prioritizes simplicity and maintainability over performance.

