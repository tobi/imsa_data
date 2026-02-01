---
name: imsa
description: Query the IMSA DuckDB dataset (output/imsa.duckdb). Includes schema guidance for seasons and laps plus formatting macros. Use for analytics, session lookups, and lap-level queries.
---

# IMSA DuckDB Skill

Use this skill when working with the IMSA database in this repo.

## Dataset

- Database: `output/imsa.duckdb`
- Primary entry points:
  - `seasons` view (session-level summary)
  - `laps` table (lap-by-lap records)

## Quick Start

```sql
SELECT *
FROM seasons
WHERE session = 'race'
ORDER BY date DESC
LIMIT 10;
```

## Schema Cheatsheet

### `seasons` view
- `date` (DATE): event start date
- `session_id` (BIGINT): join key to `laps`
- `season` (VARCHAR): 2021–2025
- `event` (VARCHAR): canonical venue name
- `session` (VARCHAR): race/practice/qualifying
- `cars`, `drivers` (BIGINT): counts
- `classes` (VARCHAR): comma-separated classes
- `session_start`, `session_end` (TIMESTAMP)
- `total_laps` (INTEGER)
- `rain_laps` (BIGINT)
- `flags` (VARCHAR): non-green flags (NULL means all green)

### `laps` table
- Session keys: `year`, `event`, `session`, `start_date`, `session_id`
- Timing: `session_time`, `clock_time`, `lap_time`, `lap_time_s1/s2/s3`
- Car/driver: `car` (string), `class`, `driver_name`, `driver_id`, `team_name`
- Lap metadata: `lap`, `lap_time_driver_rank`, `pit_time`, `flags`
- Stints: `stint_start`, `stint_number`, `stint_lap`
- License: `license`, `license_rank`, `driver_country`
- Weather: `air_temp_f`, `track_temp_f`, `humidity_percent`, `pressure_inhg`,
  `wind_speed_mph`, `wind_direction_degrees`, `raining`

### Notes
- `session_id` is a stable join key for session-level joins.
- `car` is stored as text (e.g., '01' vs '1').
- `stint_lap` is 0-based within each stint.
- Weather columns are nullable; values reuse latest reading.

## Time Formatting

Use these macros when presenting times:

```sql
format_time(t) -- MM:SS.mmm or HH:MM:SS.mmm when >= 1 hour
format_gap(t)  -- always +/- with 3 decimals
```

Examples:
- `format_time(117.099)` → `01:57.099`
- `format_time(3661.234)` → `01:01:01.234`
- `format_gap(4.323)` → `+4.323`

## Example Queries

Fastest laps per driver in a race:

```sql
SELECT
  driver_name,
  MIN(lap_time) AS best_lap
FROM laps
WHERE session_id = ?
GROUP BY driver_name
ORDER BY best_lap;
```

Track rain sessions:

```sql
SELECT date, event, session, rain_laps
FROM seasons
WHERE rain_laps > 0
ORDER BY date DESC;
```
