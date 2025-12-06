# IMSA Data SQLMesh Project

This directory contains the SQLMesh-based data transformation pipeline for the IMSA endurance racing data platform. SQLMesh replaces direct DuckDB/SQL scripts with a modern data transformation framework that provides:

- **Virtual Data Environments**: Preview changes before production deployment
- **Incremental Processing**: Only rebuild what's changed
- **Built-in Audits**: Data quality checks at every transformation step
- **Column-Level Lineage**: Track data flow through the pipeline
- **Plan/Apply Workflow**: Similar to Terraform for data

## Project Structure

```
sqlmesh_project/
├── pyproject.toml           # Project config and dependencies
├── scripts.py               # CLI command implementations
├── config.yaml              # SQLMesh configuration
├── macros/                  # Reusable SQL macros
│   └── __init__.py          # Python-defined macros (clean_event_name, parse_time, etc.)
├── seeds/                   # Static reference data
│   └── class_mapping.csv    # Cross-series class normalization
├── models/                  # SQLMesh models
│   ├── staging/             # Raw data extraction
│   │   ├── seed_class_mapping.sql
│   │   ├── stg_event_drivers.sql
│   │   ├── stg_event_laps.sql
│   │   └── stg_event_weather.sql
│   ├── intermediate/        # (reserved for future use)
│   └── marts/               # Final output tables
│       ├── drivers.sql
│       ├── laps.sql
│       ├── laps_with_bpillar.sql
│       ├── laps_normalized.sql
│       ├── laps_with_metadata.sql
│       ├── event_metadata.sql
│       ├── seasons.sql
│       └── views/           # Convenience views
│           ├── laps_imsa.sql
│           ├── laps_wec.sql
│           ├── laps_elms.sql
│           ├── laps_alms.sql
│           ├── laps_imsa_2024.sql
│           ├── laps_imsa_2025.sql
│           ├── laps_wec_2024.sql
│           └── laps_wec_2025.sql
└── audits/                  # Data quality audits
    └── data_quality.sql
```

## Installation

Install [uv](https://docs.astral.sh/uv/) if you haven't already:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Usage

All commands are run from the `sqlmesh_project` directory:

```bash
cd sqlmesh_project
```

### Build the Database

```bash
uv run scripts.py update
```

This will:
1. Run `sqlmesh plan --auto-apply` to build all models
2. Export CSVs for `drivers`, `laps`, and `seasons`
3. Create `output/imsa.duckdb` database

### Preview Changes (Plan)

```bash
uv run scripts.py plan
```

Shows what would be built without making changes.

### Apply Changes

```bash
uv run scripts.py apply
```

Applies pending changes without interactive prompts.

### Run Audits

```bash
uv run scripts.py audit
```

Validates data quality across all models.

### Launch SQLMesh UI

```bash
uv run scripts.py ui
```

Opens a web-based interface for exploring models, lineage, and diffs.

### View DAG

```bash
uv run scripts.py dag
```

Shows the model dependency graph.

### Export CSVs

```bash
uv run scripts.py export
```

Exports tables to CSV files without rebuilding.

### Open Database Shell

```bash
uv run scripts.py shell
```

Opens DuckDB interactive shell with the database.

## All Commands

| Command | Description |
|---------|-------------|
| `uv run scripts.py update` | Build database and export CSVs |
| `uv run scripts.py plan` | Preview changes (interactive) |
| `uv run scripts.py apply` | Apply changes (non-interactive) |
| `uv run scripts.py audit` | Run data quality audits |
| `uv run scripts.py ui` | Launch web UI |
| `uv run scripts.py dag` | Show model DAG |
| `uv run scripts.py test` | Run SQLMesh tests |
| `uv run scripts.py export` | Export tables to CSV |
| `uv run scripts.py shell` | Open DuckDB shell |

## Model Hierarchy

```
CSV Files (data/*/*/*.csv)
    ↓
┌───────────────────────────────────────────────────┐
│ STAGING LAYER                                     │
├───────────────────────────────────────────────────┤
│ stg_event_drivers  ← results.csv (unpivots 6 drivers) │
│ stg_event_laps     ← laps.csv (stint detection)  │
│ stg_event_weather  ← weather.csv (relative time) │
│ seed_class_mapping ← class_mapping.csv           │
└───────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────┐
│ MARTS LAYER                                       │
├───────────────────────────────────────────────────┤
│ drivers            ← snapshot of latest driver info │
│ laps               ← joins drivers + weather + class │
│ laps_with_bpillar  ← adds bpillar quartile       │
│ laps_normalized    ← cross-series class comparison │
│ laps_with_metadata ← adds event metadata         │
│ event_metadata     ← circuit info, race duration │
│ seasons            ← session summary             │
└───────────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────────┐
│ VIEWS (Convenience Filters)                       │
├───────────────────────────────────────────────────┤
│ laps_imsa, laps_wec, laps_elms, laps_alms        │
│ laps_imsa_2024, laps_imsa_2025, etc.             │
└───────────────────────────────────────────────────┘
```

## Macros

The following macros are available in all models:

| Macro | Description |
|-------|-------------|
| `@clean_event_name(event)` | Normalizes circuit names from folder names |
| `@license_rank(license)` | Converts license letters (P/G/S/B) to numeric ranks (5/4/3/2) |
| `@parse_time(time_str)` | Parses various time formats to decimal seconds |
| `@format_time(seconds)` | Formats decimal seconds as MM:SS.mmm |
| `@format_gap(seconds)` | Formats time gap with sign (+4.323) |

## Audits

Built-in audits validate:
- Unique lap records per session/car
- Non-null required fields (session_id, car, lap, driver_name)
- Valid lap numbers (positive integers)
- Valid bpillar quartile values (1-4 when set)

## Key Tables

### `marts.laps_with_bpillar`
The main analysis table with 40+ columns including:
- Series/event identification
- Driver and team info
- Lap timing (total, sectors, pit)
- Performance ranking (bpillar quartile)
- Weather conditions
- Normalized class mapping

### `marts.drivers`
Snapshot of latest driver information across all sessions.

### `marts.seasons`
Summary statistics by session with car/driver counts, duration, flags.

### `marts.event_metadata`
Circuit information, race duration, event classification (Sprint/Endurance/Ultra-Endurance).

## Migration from Raw SQL

This SQLMesh project replaces the numbered SQL files (000-008) in the root directory:

| Old File | New SQLMesh Model |
|----------|-------------------|
| 000-settings.sql | macros/__init__.py |
| 001-event-drivers.sql | models/staging/stg_event_drivers.sql |
| 002-event-laps.sql | models/staging/stg_event_laps.sql |
| 003-event-weather.sql | models/staging/stg_event_weather.sql |
| 004-laps.sql | models/marts/laps.sql |
| 005-season-views.sql | models/marts/seasons.sql + views/* |
| 006-bpillar.sql | models/marts/laps_with_bpillar.sql |
| 007-class-normalization.sql | seeds/class_mapping.csv + seed_class_mapping.sql |
| 008-event-metadata.sql | models/marts/event_metadata.sql |

## Environment Configuration

The `config.yaml` file configures:
- DuckDB as the default gateway
- Database path: `./output/imsa.duckdb`
- Default dialect: duckdb
- Model cron schedule: @daily

To use a different database location, update the `database` path in config.yaml.
