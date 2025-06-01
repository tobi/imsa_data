# IMSA Data Scraper

A simplified Ruby tool that collects IMSA WeatherTech Championship event data from the official results website and converts it into a DuckDB database for analysis.

## Features

- **Simple**: No external dependencies - uses only Ruby standard library
- **Organized**: Clean object-oriented design with proper error handling
- **Flexible**: Configurable year, output path, and series pattern
- **Robust**: Handles network errors and missing files gracefully

## Using this dataset

Data is published to https://huggingface.co/datasets/tobil/imsa. CSVs are there fore easy use in libraries, but duckdb is also there. An easy way to access it is via duckdb directly supporting huggingface:

```bash
duckdb "hf://datasets/tobil/imsa/imsa.duckdb"
DuckDB v1.3.0 (Ossivalis) 71c5c07cdd
Enter ".help" for usage hints.
D select year, event, class, MIN(lap_time), min_by(driver_name, lap_time) as best_lap_by,  AVG(lap_time) FROM laps WHERE class='LMP2' AND license = 'Bronze' AND session='race' GROUP BY year, event, class ORDER BY year;
┌─────────┬───────────────────────────────┬─────────┬───────────────┬─────────────────┬────────────────────┐
│  year   │             event             │  class  │ min(lap_time) │   best_lap_by   │   avg(lap_time)    │
│ varchar │            varchar            │ varchar │ decimal(10,3) │     varchar     │       double       │
├─────────┼───────────────────────────────┼─────────┼───────────────┼─────────────────┼────────────────────┤
│ 2021    │ Sebring                       │ LMP2    │       109.619 │ Thomas Merrill  │ 130.18216857798166 │
│ 2021    │ Road America                  │ LMP2    │       118.042 │ Ben Keating     │  141.5948546511628 │
│ 2021    │ Laguna Seca                   │ LMP2    │        79.459 │ Ben Keating     │  94.20574166666667 │
│ 2021    │ Road Atlanta                  │ LMP2    │        71.708 │ Thomas Merrill  │  92.71410285220398 │
│ 2021    │ Watkins Glen                  │ LMP2    │        94.178 │ Thomas Merrill  │ 112.89046144121366 │
[...]
```

or ruby like 
```ruby
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'duckdb'
end

require 'duckdb'
conn = DuckDB::Database.new("hf://datasets/tobil/imsa/imsa.duckdb")
puts conn.query("SELECT COUNT(*) FROM drivers")
```

Or use any standard huggingface python libraries 

```python
from datasets import load_dataset

# Login using e.g. `huggingface-cli login` to access this dataset
ds_laps = load_dataset("tobil/imsa", "laps")
ds_driver = load_dataset("tobil/imsa", "drivers")
```

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

### Database Tables

The DuckDB database contains several key tables:

#### `laps` Table (Primary Analysis Table)

The main `laps` table combines lap data with driver information and weather conditions. Each row represents a single lap with the following columns:

**Event & Session Information:**
- `session_id` - Unique identifier for each session across all years/events
- `year` - Race year (e.g., 2024)
- `event` - Event name (e.g., "daytona-international-speedway")
- `session` - Session type ("race", "qualifying", "practice", etc.)
- `start_date` - Session start date and time

**Lap Data:**
- `lap` - Lap number within the session
- `car` - Car number
- `lap_time` - Individual lap time (TIME format)
- `session_time` - Elapsed time from session start (TIME format)
- `clock_time` - Wall clock time when lap was completed
- `pit_time` - Time spent in pit (if applicable)
- `flags` - Flag conditions during the lap
- `class` - Racing class (GTD, GTP, LMP2, etc.)

**Driver Information:**
- `driver_name` - Driver name
- `license` - FIA license level (Platinum, Gold, Silver, Bronze)
- `license_rank` - Numeric license rank (5=Platinum, 4=Gold, 3=Silver, 2=Bronze)
- `driver_country` - Driver's country
- `team_name` - Team name
- `stint_start` - Boolean indicating if this lap starts a new stint
- `stint_number` - Sequential stint number for this driver/car combination

**Weather Data (from most recent reading before/at lap time):**
- `air_temp_f` - Air temperature in Fahrenheit
- `track_temp_f` - Track surface temperature in Fahrenheit
- `humidity_percent` - Relative humidity percentage
- `pressure_inhg` - Atmospheric pressure in inches of mercury
- `wind_speed_mph` - Wind speed in miles per hour
- `wind_direction_degrees` - Wind direction in degrees
- `raining` - Boolean indicating rain conditions

The weather data is intelligently matched to each lap using the most recent weather reading before or at the lap completion time, providing accurate environmental context for performance analysis.

#### Supporting Tables

**`event_laps`** - Raw lap data from CSV files with basic parsing and session identification
**`event_weather`** - Weather readings with relative time calculations for matching to laps
**`event_drivers`** - Driver information extracted from race results
**`drivers`** - Aggregated driver view with latest license and team information

#### Example Queries

```sql
-- Average lap times by weather conditions
SELECT 
    raining,
    AVG(EXTRACT(EPOCH FROM lap_time)) as avg_lap_seconds,
    COUNT(*) as laps
FROM laps 
WHERE session = 'race' AND lap_time IS NOT NULL
GROUP BY raining;

-- Driver performance in different temperature ranges
SELECT 
    driver_name,
    CASE 
        WHEN air_temp_f < 70 THEN 'Cool'
        WHEN air_temp_f < 85 THEN 'Moderate' 
        ELSE 'Hot'
    END as temp_range,
    AVG(EXTRACT(EPOCH FROM lap_time)) as avg_lap_seconds
FROM laps 
WHERE session = 'race' AND air_temp_f IS NOT NULL
GROUP BY driver_name, temp_range
ORDER BY driver_name, temp_range;
```

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
- `output/imsa.duckdb` - The main database with all tables
- `output/drivers.csv` - Driver summary data
- `output/laps.csv` - Comprehensive lap data with weather integration

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
- **`001-event-drivers.sql`** - Driver data extraction and aggregation
- **`002-event-laps.sql`** - Lap data parsing with stint analysis
- **`003-event-weather.sql`** - Weather data processing with relative time calculations
- **`004-laps.sql`** - Main analysis table combining laps, drivers, and weather

## Architecture

The code is organized into a simple `IMSAImporter` class that:

1. **Discovers events** - Finds all events for a given year
2. **Filters series** - Looks for IMSA WeatherTech events
3. **Downloads CSVs** - Gets results, laps, and weather data
4. **Converts format** - Transforms semicolon-separated to comma-separated CSV
5. **Organizes files** - Saves in a clean directory structure

The design prioritizes simplicity and maintainability over performance.

