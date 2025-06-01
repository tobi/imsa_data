---
license: mit
tags:
- racing
- imsa
- motorsport
- lap-times
- weather
- automotive
configs:
- config_name: laps
  data_files: "laps.csv"
  default: true
- config_name: drivers
  data_files: "drivers.csv"
---

# IMSA WeatherTech Championship Racing Dataset

This dataset contains comprehensive lap-by-lap data from the IMSA WeatherTech SportsCar Championship, including detailed timing information, driver data, and weather conditions for each lap.

## Dataset Details

### Dataset Description

The IMSA Racing Dataset provides detailed lap-by-lap telemetry and contextual data from the IMSA WeatherTech SportsCar Championship races from 2021-2025. The primary table contains individual lap records with integrated driver information and weather conditions, making it ideal for motorsport performance analysis, weather impact studies, and racing strategy research.

- **Curated by:** IMSA Data Scraper Project
- **Language(s):** English (driver names, team names, location names)
- **License:** MIT

### Dataset Sources

- **Repository:** [IMSA Data Scraper](https://github.com/tobi/imsa_data)
- **Data Source:** Official IMSA WeatherTech Championship results website ( https://imsa.results.alkamelcloud.com/Results/ )

This currently only includes IMSA WeatherTech Challange, and not the other IMSA events

## Uses

### Direct Use

This dataset is suitable for:
- **Motorsport Performance Analysis**: Analyze lap times, driver performance, and team strategies
- **Weather Impact Studies**: Examine how weather conditions affect racing performance
- **Machine Learning**: Predict lap times, race outcomes, or optimal strategies
- **Sports Analytics**: Compare driver and team performance across different conditions
- **Educational Research**: Study motorsport data science and racing dynamics

### Out-of-Scope Use

- Personal identification of drivers beyond publicly available racing information
- Commercial use without proper attribution to IMSA and data sources
- Analysis requiring real-time or live timing data

## Dataset Structure

The primary table is `laps`, where each row represents a single lap completed by a driver during a racing session.

### Key Columns

**Event & Session Information:**
- `session_id`: Unique identifier for each racing session
- `year`: Race year (2021-2025)
- `event`: Event name (e.g., "daytona-international-speedway")
- `session`: Session type ("race", "qualifying", "practice")
- `start_date`: Session start date and time

**Lap Performance Data:**
- `lap`: Lap number within the session
- `car`: Car number
- `lap_time`: Individual lap time (TIME format)
- `session_time`: Elapsed time from session start
- `pit_time`: Time spent in pit stops
- `class`: Racing class (GTD, GTP, LMP2, etc.)

**Driver Information:**
- `driver_name`: Driver name
- `license`: FIA license level (Platinum, Gold, Silver, Bronze)
- `driver_country`: Driver's country
- `team_name`: Team name
- `stint_number`: Sequential stint number for driver/car

**Weather Conditions:**
- `air_temp_f`: Air temperature (Fahrenheit)
- `track_temp_f`: Track surface temperature (Fahrenheit)
- `humidity_percent`: Relative humidity
- `pressure_inhg`: Atmospheric pressure
- `wind_speed_mph`: Wind speed
- `wind_direction_degrees`: Wind direction
- `raining`: Boolean flag for rain conditions

### Data Statistics

The dataset typically contains:
- **~50,000+ laps** across all years and sessions
- **200+ drivers** from various countries and license levels
- **100+ teams** competing across different classes
- **40+ events** per year across multiple racing venues
- **Weather data** matched to each lap for environmental analysis

## Dataset Creation

### Curation Rationale

This dataset was created to provide comprehensive, structured access to IMSA racing data for research and analysis purposes. The integration of lap times with weather conditions and driver information enables sophisticated motorsport analytics that would otherwise require manual data correlation.

### Source Data

#### Data Collection and Processing

Data is collected from the official IMSA WeatherTech Championship results website using automated scraping tools. The processing pipeline:

1. **Event Discovery**: Identifies all racing events for specified years
2. **Data Extraction**: Downloads race results, lap times, and weather data
3. **Data Integration**: Matches weather conditions to individual laps using temporal correlation
4. **Driver Enrichment**: Adds driver license levels, countries, and team information
5. **Quality Assurance**: Validates data consistency and handles missing values

#### Who are the source data producers?

The source data is produced by:
- **IMSA (International Motor Sports Association)**: Official race timing and results
- **Racing teams and drivers**: Performance data during competition
- **Weather monitoring systems**: Environmental conditions at racing venues

## Technical Implementation

The dataset is generated using:
- **Ruby-based scraper**: Collects data from official sources
- **DuckDB database**: Stores and processes the integrated dataset
- **SQL transformations**: Creates the final analytical tables