# MotorsportDB

A comprehensive endurance racing database covering **IMSA WeatherTech**, **WEC** (including 24h Le Mans), **ELMS**, **Asian Le Mans**, and **Le Mans Cup**. Built with Ruby and DuckDB.

## Quick Start

```bash
# Access the database directly from HuggingFace
duckdb "hf://datasets/tobil/imsa/imsa.duckdb"

# Example: Fastest LMDh lap times by manufacturer
SELECT manufacturer, chassis, MIN(lap_time) as fastest
FROM laps
WHERE homologation = 'LMDh' AND session = 'race'
GROUP BY manufacturer, chassis
ORDER BY fastest;
```

## Data Coverage

| Series | Years | Events | Notable Races |
|--------|-------|--------|---------------|
| IMSA WeatherTech | 2020-2026 | 60+ | 24h Daytona, 12h Sebring, Petit Le Mans |
| WEC | 2020-2025 | 50+ | **24 Hours of Le Mans**, Spa, Bahrain |
| ELMS | 2020-2025 | 30+ | 4 Hours races across Europe |
| Asian Le Mans | 2020-2025 | 20+ | Dubai, Abu Dhabi |
| Le Mans Cup | 2020-2025 | 20+ | LMP3 & GT3 support series |

## Key Features

- **Multi-Series Support**: IMSA, WEC, ELMS, Asian Le Mans, Le Mans Cup
- **Chassis & Homologation Data**: Track LMDh vs LMH vs GT3 performance
- **Weather Integration**: Temperature, humidity, rain conditions per lap
- **Driver Licensing**: FIA license levels (Platinum/Gold/Silver/Bronze)
- **Cross-Series Analysis**: Normalized classes for comparing across series

## Project Structure

```
motorsportdb/
├── data/                      # Raw CSV data by series/year/event
│   ├── imsa/
│   │   ├── 2021/
│   │   │   ├── 01-daytona-international-speedway/
│   │   │   │   ├── 202101301340-race-laps.csv
│   │   │   │   ├── 202101301340-race-results.csv
│   │   │   │   └── 202101301340-race-weather.csv
│   │   │   └── events.json    # Event manifest with names
│   │   └── ...
│   ├── wec/
│   ├── elms/
│   ├── alms/
│   └── lmc/
│
├── output/                    # Generated database and exports
│   ├── imsa.duckdb           # Main DuckDB database
│   ├── laps.csv              # Full lap data export
│   ├── drivers.csv           # Driver summary
│   └── seasons.csv           # Season overview
│
├── SQL Schema Files           # Processed in order (000 → 110)
│   ├── 000-settings.sql      # Tracks, classes, macros
│   ├── 010-event-drivers.sql # Driver extraction from results
│   ├── 011-chassis.sql      # Chassis homologation lookup
│   ├── 013-event-results.sql # Results ingestion
│   ├── 020-event-laps.sql    # Lap parsing with stints
│   ├── 030-event-weather.sql # Weather data processing
│   ├── 040-laps.sql          # Main laps table with weather join
│   ├── 050-season-views.sql  # Year/series-specific views
│   ├── 060-bpillar.sql       # BPillar performance filtering
│   ├── 070-class-normalization.sql  # Cross-series class mapping
│   ├── 071-events.sql        # Events table
│   ├── 080-event-metadata.sql       # Circuit details, race types
│   ├── 090-driver-identity.sql      # Driver identity and normalization
│   ├── 100-driver-matching.sql      # Driver matching and merging
│   └── 110-driver-ratings.sql       # Driver ratings
│
├── Configuration Files
│   ├── tracks.json           # 45 circuits with coordinates & aliases
│   ├── classes.json          # Main series classes (filters support series)
│   └── chassis.json          # Chassis → homologation/manufacturer mapping
│
├── Quality Assurance
│   ├── lint/
│   │   ├── check_database.rb    # Schema and data integrity checks
│   │   └── check_data_quality.rb # Race session analysis
│   └── test_database.rb      # Database tests
│
├── Skills (Claude Code)
│   └── skills/
│       ├── imsa/             # IMSA analysis skill
│       └── marimo/           # Notebook generation skill
│
├── import.rb                 # Multi-series data importer
└── Rakefile                  # Build tasks
```

## Database Schema

### Main Tables

#### `laps` - Primary Analysis Table
Every lap with driver, team, chassis, and weather data.

| Column | Description |
|--------|-------------|
| `series_code` | Series identifier (imsa, wec, elms, alms, lmc) |
| `year`, `event`, `session` | When and where |
| `session_id` | Unique session identifier for joins |
| `car`, `class` | Car number and racing class |
| `driver_name`, `driver_id` | Driver info (id is stable across name variants) |
| `lap`, `lap_time` | Lap number and duration |
| `chassis` | Full chassis name (e.g., "Porsche 963") |
| `homologation` | Regulatory category: LMDh, LMH, DPi, LMP2, LMP3, GTE, GT3 |
| `manufacturer` | Car manufacturer |
| `license`, `license_rank` | FIA license level and numeric rank |
| `stint_number`, `stint_lap` | Stint tracking |
| `air_temp_f`, `track_temp_f`, `raining` | Weather conditions |

#### `seasons` - Session Summary View
High-level overview of all sessions.

#### `drivers` - Driver Directory
Aggregated driver info with latest license and team.

#### `driver_elo` - Skill Rating History (OpenSkill, two-pool)
Lap-by-lap skill ratings computed independently per class by `compute_skill.py`
using **OpenSkill** (Plackett-Luce — multiplayer, MIT-licensed, patent-free).

**Model.** Each green-flag (`flags='GF'`), non-pit lap is bucketed into a
10-minute wall-clock window by its mid-point `session_time`, so a driver is only
ranked against same-class cars actually circulating alongside them. Each driver
contributes one representative lap per window (median of their green laps); the
window's pace ranking is a single multiplayer OpenSkill match. Two pools are
emitted:

* **Overall** (license-seeded, full field): `skill_mu` / `skill_sigma` /
  `ordinal`, plus the readable `elo`. Starting `mu` is seeded by FIA license
  (Bronze 22 < Silver 25 < Gold 28 < Platinum 31) so the pool starts near tier
  equilibrium instead of deflating Ams for dozens of races.
* **Peer** (within-license tier): `peer_mu` / `peer_sigma` / `peer_ordinal`,
  plus the readable `peer_elo` — "how good are you *for* your license class". A
  Bronze who beats other Bronzes climbs here even while the overall pool docks
  them against pro traffic.

Confidence: `ordinal = mu - 3*sigma` (conservative rating; small-sample drivers
sit lower until sigma tightens). Events with no flag data fall back to all valid
racing laps.

**Time-aware confidence.** Before each event a returning driver's `sigma` is
widened for the time since they last raced — `sigma' = min(sqrt(sigma² +
(3.0·years)²), prior)` — so a long layoff lowers the conservative `ordinal`
(and `elo`) until the next race re-confirms pace. `mu` is left untouched: we
don't assume a returnee got slower, only that we're less certain.

**Relatable elo.** `elo` and `peer_elo` are 1500-centered transforms of the
conservative `ordinal`, anchored on the **actual field median** (established
drivers with ≥100 green laps): `elo = 1500 + 25·(ordinal − class_median)` and
`peer_elo = 1500 + 25·(peer_ordinal − license_median)`. So **1500 = a median
driver in your class** (overall) / **a median driver of your license** (peer).
The fixed per-class/tier anchor maps every historical row, so trajectories are
comparable over time.

| Column | Type | Description |
|--------|------|-------------|
| `driver_id` | VARCHAR | Normalized driver identifier |
| `driver_name` | VARCHAR | Display name |
| `class` | VARCHAR | GTP, LMP2, GTD, etc. (independent pools) |
| `series_code` | VARCHAR | imsa, wec, elms |
| `year` | VARCHAR | Season year |
| `event` | VARCHAR | Event name |
| `session_date` | TIMESTAMP | Event date |
| `laps` | INTEGER | Green laps driven in event |
| `cumulative_laps` | INTEGER | Career green laps in class |
| `license` | VARCHAR | FIA license tier |
| `skill_mu` / `skill_sigma` / `ordinal` | DOUBLE | Overall pool skill / uncertainty / conservative rating |
| `elo` | INTEGER | Relatable overall rating (1500 = class median) |
| `peer_mu` / `peer_sigma` / `peer_ordinal` | DOUBLE | Within-tier pool equivalents |
| `peer_elo` | INTEGER | Relatable peer rating (1500 = license-tier median) |

Ratings are computed in a local Python venv (`compute_skill.py`, OpenSkill +
DuckDB); the Rake task bootstraps it on first run.

```sql
-- Current overall + peer rating for a driver
SELECT driver_name, elo, ordinal, peer_ordinal, cumulative_laps
FROM driver_elo_current
WHERE driver_id = 'tobi lutke' AND class = 'LMP2';

-- Overall leaderboard (conservative rating)
SELECT driver_name, ordinal, cumulative_laps FROM driver_elo_current
WHERE class = 'GTP' ORDER BY ordinal DESC LIMIT 10;

-- Within-license (peer) leaderboard
SELECT peer_rank, driver_name, peer_ordinal FROM driver_peer_current
WHERE class = 'LMP2' AND license = 'Bronze' ORDER BY peer_rank LIMIT 10;
```

#### `driver_elo_current` - Current Rating View
Pre-aggregated leaderboard: latest overall + peer ratings (with sigma), readable
elo, total laps, and event counts per driver/class.

#### `driver_peer_current` - Within-License Leaderboard
Ranks drivers against same-license peers per class (`peer_rank`).

#### `tracks` - Circuit Database
Track coordinates and metadata from `tracks.json`.

#### `chassis_homologation` - Chassis Mapping
Maps chassis names to homologation categories.

### Homologation Categories

| Category | Description | Example Chassis |
|----------|-------------|-----------------|
| LMDh | Le Mans Daytona hybrid | Porsche 963, Cadillac V-Series.R, BMW M Hybrid V8 |
| LMH | Le Mans Hypercar | Toyota GR010, Ferrari 499P, Peugeot 9X8 |
| DPi | Daytona Prototype international | Cadillac DPi, Acura DPi (discontinued) |
| LMP2 | Le Mans Prototype 2 | Oreca 07, Dallara LMP2 |
| LMP3 | Le Mans Prototype 3 | Ligier JS P320, Duqueine D08 |
| GTE | GT Endurance | Corvette C8.R, Ferrari 488 GTE |
| GT3 | GT3 specification | Ferrari 296 GT3, Porsche 911 GT3 R |

## Usage

### Import Data

```bash
# Import a specific series/year
ruby import.rb imsa 2024
ruby import.rb wec 2024
ruby import.rb elms 2024

# Or use rake tasks
rake import              # IMSA current year
rake import_wec          # WEC current year
rake import_all[2024]    # All series for 2024
```

### Build Database

```bash
rake db:update           # Build/rebuild database
rake db:open             # Open in DuckDB CLI
```

### Run Checks

```bash
rake lint                # Database integrity checks
rake lint_data           # Data quality analysis
rake check               # Full check (db:update + lint + lint_data)
```

## Analysis Principles

### Critical Rules
1. **Never compare lap times across different events** - Track conditions, weather, and layouts vary too much
2. **Never compare lap times across different classes** - GTP, LMP2, GTD are completely different cars
3. **Always filter by session_id for meaningful comparisons** - This ensures same track/conditions
4. **Default to race sessions** - Practice and qualifying have different strategies

### BPillar Quartiles
The `bpillar_quartile` column (race sessions only) intelligently filters laps for representative pace:

| Quartile | Meaning | Use for |
|----------|---------|---------|
| 1 | Fastest 25% | Pure pace analysis |
| 2 | 25-50% | Good representative pace |
| 3 | 50-75% | Traffic, marginal conditions |
| 4 | Slowest 25% | Pit laps, cautions, issues |
| NULL | Excluded | First lap, pit in/out, outliers |

**Best practice**: Filter to `bpillar_quartile IN (1, 2)` for pace analysis. This automatically excludes:
- First lap of the race
- Pit in/out laps
- Laps under caution
- Laps with traffic or issues

### Weather Considerations
- Check `raining` column for wet conditions
- Wet and dry lap times are NOT comparable
- Temperature affects tire performance significantly
- Use `air_temp_f` and `track_temp_f` for analysis

#### Temperature units (deterministic, single-pass)
All temperatures in the database are **Fahrenheit**. Units are a fixed per-series
property of the source timing feed — IMSA reports °F; WEC, ELMS, ALMS and Le Mans
Cup report °C (see `SERIES_CONFIG[:temperature_unit]` in `import.rb` and
`data/series.json`). `import.rb` performs the **one and only** unit conversion when
it writes the CSVs, so every weather file on disk is already °F. The SQL pipeline
therefore never converts again — the `temperature()` macro is a documented
pass-through.

This replaced an earlier value-based heuristic (guess Celsius if a sample median
was below ~45) that misfired on cold races and could double-convert, producing
impossible track temps (a real 70°F Spa surface became 158°F). Heuristics are now
used for **validation only**: `030-event-weather.sql` nulls physically-impossible
sensor readings (air outside 32–140°F, track outside 35–200°F), and
`lint/check_database.rb` flags any event whose temps still look like unconverted
Celsius.

#### Weather ↔ laps alignment
The `laps` table joins weather on the natural session key
`(series_code, year, event_folder, session_type, start_date)`, **not** on a synthetic
`session_id`. The two tables assign `session_id` via independent `DENSE_RANK()`s over
different row populations, so equal ids do not denote the same session; matching on id
previously bound, e.g., Daytona's race to an unrelated event's weather. Per-hour race
weather files (`...-race-hour-N-weather.csv`) collapse into a single race timeline so
`relative_seconds` measures elapsed time from race start.

## Example Queries

### Compare LMDh vs LMH Performance
```sql
SELECT
    homologation,
    manufacturer,
    COUNT(DISTINCT driver_id) as drivers,
    MIN(lap_time) as fastest_lap,
    AVG(lap_time) as avg_lap
FROM laps
WHERE class IN ('GTP', 'HYPERCAR')
    AND session = 'race'
    AND bpillar_quartile IN (1, 2)
GROUP BY homologation, manufacturer
ORDER BY fastest_lap;
```

### Find Drivers Racing in Multiple Series
```sql
SELECT
    driver_name,
    STRING_AGG(DISTINCT series_code, ', ') as series,
    COUNT(DISTINCT event) as events
FROM laps
WHERE year = '2024'
GROUP BY driver_name
HAVING COUNT(DISTINCT series_code) > 1
ORDER BY events DESC;
```

### Weather Impact Analysis
```sql
SELECT
    CASE WHEN raining THEN 'Wet' ELSE 'Dry' END as conditions,
    class,
    AVG(lap_time) as avg_lap,
    COUNT(*) as laps
FROM laps
WHERE session = 'race' AND event = 'Le Mans'
GROUP BY raining, class
ORDER BY class, conditions;
```

## Data Sources

All data is collected from Al Kamel Systems timing infrastructure used by ACO-sanctioned series.

## License

MIT

## Contributing

1. Add new tracks to `tracks.json`
2. Add new chassis to `chassis.json`
3. Run `rake check` to validate changes
