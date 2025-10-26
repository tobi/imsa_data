# Endurance Racing Data Scraper

A simplified Ruby tool that collects endurance racing event data from official timing websites and converts it into a DuckDB database for analysis. Supports **IMSA WeatherTech**, **WEC** (including 24h Le Mans), **ELMS**, **Asian Le Mans**, and **Le Mans Cup**.

## Features

- **Multi-Series Support**: Import data from IMSA, WEC, ELMS, Asian Le Mans, and Le Mans Cup
- **Simple**: No external dependencies - uses only Ruby standard library
- **Organized**: Clean object-oriented design with proper error handling
- **Flexible**: Configurable series, year, and output path
- **Cross-Series Analysis**: Normalized class names and metadata for comparing across series
- **Robust**: Handles network errors and missing files gracefully

## Supported Series

All series use Al Kamel Systems timing infrastructure:

| Series Code | Full Name | Notable Events |
|-------------|-----------|----------------|
| `imsa` | IMSA WeatherTech Championship | 24h Daytona, 12h Sebring, Petit Le Mans |
| `wec` | FIA World Endurance Championship | **24 Hours of Le Mans**, Spa, Bahrain |
| `elms` | European Le Mans Series | 4 Hours races across Europe |
| `alms` | Asian Le Mans Series | 4 Hours races across Asia |
| `lmc` | Le Mans Cup | LMP3 & GT3 support series |

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

Downloaded CSV files are organized in the `data/` directory by series and year:

```
data/
├── imsa/
│   ├── 2024/
│   │   ├── 01-roar-before-the-24/
│   │   │   ├── 202401260800_race-results.csv
│   │   │   ├── 202401260800_race-laps.csv
│   │   │   └── 202401260800_race-weather.csv
│   │   └── 02-twelve-hours-of-sebring/
│   │       └── ...
│   └── 2023/
│       └── ...
├── wec/
│   └── 2024/
│       ├── 01-qatar/
│       ├── 02-imola/
│       ├── 03-spa/
│       └── 04-le-mans/  ← 24 Hours of Le Mans!
│           └── ...
├── elms/
│   └── 2024/
│       └── ...
└── alms/
    └── 2024/
        └── ...
```

Each event contains three types of CSV files per session:
- **results**: Race finishing positions and times
- **laps**: Individual lap times and data
- **weather**: Weather conditions during the session

**Note:** Legacy data in `data/year/...` format is automatically recognized as IMSA data.

### Database Tables

The DuckDB database contains several key tables:

#### `laps` Table (Primary Analysis Table)

The main `laps` table combines lap data with driver information and weather conditions. Each row represents a single lap with the following columns:

**Series Identification (NEW!):**
- `series_code` - Series identifier ("imsa", "wec", "elms", "alms", "lmc")
- `series` - Combined series-year ("imsa-2024", "wec-2024", etc.)

**Event & Session Information:**
- `start_date` - Session start date and time
- `year` - Race year (e.g., 2024)
- `event` - Event name (e.g., "daytona-international-speedway", "le-mans")
- `session` - Session type ("race", "qualifying", "practice", etc.)
- `session_id` - Unique identifier for each session across all series/years/events

**Car & Driver:**
- `car` - Car number
- `class` - Racing class (GTP, Hypercar, LMP2, LMGT3, etc.)
- `class_normalized` - Normalized class for cross-series comparison (NEW!)
- `class_category` - High-level category ("Top Prototype", "LMP2", "GT Professional", etc.) (NEW!)
- `driver_name` - Driver name

**Lap Timing:**
- `session_time` - Elapsed time from session start (TIME format)
- `clock_time` - Wall clock time when lap was completed
- `session_time_lap_number` - Virtual lap counter derived from session timing; aligns every car with the lap the field is on even after long pit repairs
- `lap` - Lap number within the session
- `lap_time` - Individual lap time (TIME format)
- `lap_time_driver_rank` - Per-driver ranking of `lap_time` within the session; 1 is that driver's fastest completed lap (NULL for missing lap times)
- `pit_time` - Time spent in pit (if applicable)
- `flags` - Flag conditions during the lap

**Stint Tracking:**
- `stint_start` - Boolean indicating if this lap starts a new stint
- `stint_number` - Sequential stint number for the car inside the session; increments whenever `stint_start` flips to 1
- `stint_lap` - Zero-based lap index within the current stint (out laps and first laps are 0)

**Licensing & Team:**
- `license` - FIA license level (Platinum, Gold, Silver, Bronze)
- `license_rank` - Numeric license rank (5=Platinum, 4=Gold, 3=Silver, 2=Bronze)
- `driver_country` - Driver's country
- `team_name` - Team name

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
**`class_mapping`** - Maps original class names to normalized categories (NEW!)
**`event_metadata`** - Circuit details, race duration, event types (NEW!)

#### Series and Season Views

**Series-specific views (all sessions):**
- `laps_imsa` - All IMSA data
- `laps_wec` - All WEC data (including Le Mans!)
- `laps_elms` - All ELMS data
- `laps_alms` - All Asian Le Mans data
- `laps_lmc` - All Le Mans Cup data

**Series + Year views (race sessions only):**
- `laps_imsa_2024`, `laps_imsa_2023`, etc.
- `laps_wec_2024`, `laps_wec_2025`
- `laps_elms_2024`, `laps_elms_2025`
- `laps_alms_2024`, etc.

**Legacy year-only views (backward compatible, shows all series):**
- `laps_2021`, `laps_2022`, `laps_2023`, `laps_2024`, `laps_2025`

**Cross-series analysis views:**
- `laps_normalized` - Includes `class_std` and `category_std` fields for cross-series comparison
- `laps_with_metadata` - Joins laps with event metadata (circuit names, duration, etc.)
- `seasons` - Summary view of all sessions by series/year/event

#### Example Queries

**Single series analysis:**
```sql
-- IMSA 2024 race data
SELECT * FROM laps_imsa_2024;

-- WEC data including Le Mans
SELECT * FROM laps WHERE series_code = 'wec' AND event LIKE '%le-mans%';
```

**Cross-series comparison:**
```sql
-- Compare LMP2 performance across all series
SELECT
    series,
    MIN(lap_time) as fastest_lap,
    AVG(lap_time) as average_lap,
    COUNT(*) as laps
FROM laps_normalized
WHERE class_category = 'LMP2' AND session = 'race'
GROUP BY series
ORDER BY fastest_lap;

-- Find drivers competing in multiple series
SELECT
    driver_name,
    COUNT(DISTINCT series_code) as num_series,
    STRING_AGG(DISTINCT series ORDER BY series) as series_list
FROM laps
WHERE year = '2024'
GROUP BY driver_name
HAVING COUNT(DISTINCT series_code) > 1
ORDER BY num_series DESC;
```

**Weather analysis:**
```sql
-- Average lap times by weather conditions across all series
SELECT
    series_code,
    raining,
    AVG(EXTRACT(EPOCH FROM lap_time)) as avg_lap_seconds,
    COUNT(*) as laps
FROM laps
WHERE session = 'race' AND lap_time IS NOT NULL
GROUP BY series_code, raining
ORDER BY series_code, raining;
```

**Event metadata analysis:**
```sql
-- Compare performance by race duration
SELECT
    event_type,
    class_category,
    AVG(EXTRACT(EPOCH FROM lap_time)) as avg_lap_seconds
FROM laps_with_metadata
WHERE session = 'race'
GROUP BY event_type, class_category
ORDER BY event_type, class_category;
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

**Import IMSA (default):**
```bash
ruby import.rb --series imsa --year 2024
# or simply
rake import
```

**Import WEC (includes 24 Hours of Le Mans!):**
```bash
ruby import.rb --series wec --year 2024
# or
rake import_wec
```

**Import ELMS:**
```bash
ruby import.rb --series elms --year 2024
# or
rake import_elms
```

**Import Asian Le Mans:**
```bash
ruby import.rb --series alms --year 2024
# or
rake import_alms
```

**Import all series for a given year:**
```bash
rake import_all[2024]
```

**Import IMSA for multiple recent years:**
```bash
rake import_recent  # imports last 3 years of IMSA
```

**Get help:**
```bash
ruby import.rb --help
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
  -y, --year YEAR       Year to fetch (default: current year)
  -o, --output-path PATH Output directory (default: data/)
  -s, --series SERIES   Series to import (default: imsa)
                        Options: imsa, wec, elms, alms, lmc
  -h, --help            Show help message

Examples:
  ruby import.rb --series wec --year 2024
  ruby import.rb --series elms --year 2023
```

## Files

**Data Import:**
- **`import.rb`** - Multi-series scraper with support for IMSA, WEC, ELMS, Asian Le Mans, Le Mans Cup
- **`Rakefile`** - Build tasks for database generation and data import

**Database Schema:**
- **`000-settings.sql`** - Database configuration and utility functions
- **`001-event-drivers.sql`** - Driver data extraction and aggregation
- **`002-event-laps.sql`** - Lap data parsing with stint analysis
- **`003-event-weather.sql`** - Weather data processing with relative time calculations
- **`004-laps.sql`** - Main analysis table combining laps, drivers, and weather
- **`005-season-views.sql`** - Series-specific and season-specific views
- **`006-bpillar.sql`** - Advanced stint analysis (if present)
- **`007-class-normalization.sql`** - Cross-series class mapping (NEW!)
- **`008-event-metadata.sql`** - Circuit details and race format metadata (NEW!)

**Documentation:**
- **`GENERALIZATION_PROPOSAL.md`** - Full research and design for multi-series support
- **`IMPLEMENTATION_SUMMARY.md`** - Technical implementation details

## Architecture

The code is organized into a simple `IMSAImporter` class that:

1. **Discovers events** - Finds all events for a given year
2. **Filters series** - Looks for IMSA WeatherTech events
3. **Downloads CSVs** - Gets results, laps, and weather data
4. **Converts format** - Transforms semicolon-separated to comma-separated CSV
5. **Organizes files** - Saves in a clean directory structure

The design prioritizes simplicity and maintainability over performance.
