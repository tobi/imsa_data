# IMSA Data Agent Guide

The IMSA database (`output/imsa.duckdb`) provides comprehensive racing data from
2021-2025. This guide documents the schema so downstream agents (human or
automated) can reason about the data without reverse-engineering the SQL pipeline.

## Quick Start

**Start with the `seasons` table** for a high-level overview of all sessions,
events, and races. This table provides aggregated statistics that help you
understand the scope of the data before diving into individual laps.

```sql
SELECT * FROM seasons WHERE session = 'race' ORDER BY date DESC LIMIT 10;
```

---

## The `seasons` View

The `seasons` view provides a session-level summary of every practice, qualifying,
and race session across all years. Use this table to identify which sessions exist,
when they occurred, and high-level characteristics like total laps and weather
conditions.

### Columns

| Column | Type | Description |
| --- | --- | --- |
| `date` | DATE | Event start date (first session of the event). |
| `session_id` | BIGINT | Unique identifier for this session. Use as join key with `laps` table. |
| `season` | VARCHAR | Season year (`2021`–`2025`). |
| `event` | VARCHAR | Canonical venue name (e.g., `Road America`, `Sebring`). |
| `session` | VARCHAR | Session type (`race`, `practice-1`, `practice-2`, `qualifying`, etc.). |
| `cars` | BIGINT | Count of distinct cars that participated in this session. |
| `drivers` | BIGINT | Count of distinct drivers who competed. |
| `classes` | VARCHAR | Comma-separated list of classes that participated (e.g., `GTP, LMP2, GTD`). |
| `session_start` | TIMESTAMP | Actual session start timestamp. |
| `session_end` | TIMESTAMP | Session end timestamp (computed from max session_time). |
| `total_laps` | INTEGER | Total number of laps completed across all cars. |
| `rain_laps` | BIGINT | Count of laps completed during rain conditions. |
| `flags` | VARCHAR | Distinct flag conditions during the session, excluding green flags (e.g., `FCY, RED`). |

### Usage Tips

- Filter by `session = 'race'` to focus on race sessions only
- Use `session_id` as a join key when connecting to the `laps` table
- Check `rain_laps` to quickly identify wet sessions
- The `flags` column shows non-green flag conditions; NULL means green flags only

---

## The `laps` Table

The `laps` table is the canonical surface for detailed lap-by-lap analysis,
matching every recorded lap with driver, team, and weather context.

## Row Semantics

Each row represents a single completed lap for a given car during a specific
session. Driver, team, and license values are taken from the authoritative
entry list (`event_drivers`) whenever available; the raw lap CSV values are
used only as fallbacks. Weather fields reflect the most recent observation at
or before the lap's `session_time`.

## Columns

| Column | Type | Description |
| --- | --- | --- |
| `start_date` | TIMESTAMP | Scheduled start timestamp for the session, parsed from the IMSA file name. Used in combination with `year`, `event`, and `session` to disambiguate double-header weekends (e.g., two Watkins Glen races in 2021). |
| `year` | VARCHAR | Season year (`2021`–`2025` currently). Purely textual so it can coexist with historical prefabricated datasets. |
| `event` | VARCHAR | Canonical venue name from `clean_event_name` (e.g., `Road America`, `Sebring`). Normalization prevents small spelling changes from splitting events. |
| `session` | VARCHAR | IMSA session label such as `race`, `practice-2`, `qualifying`. Mirrors the official results naming so you can correlate back to the PDFs. |
| `session_id` | BIGINT | Deterministic identifier created with `DENSE_RANK` over `(year, event, session, start_date)`. This means every unique year/event/session/start_date combination maps to exactly one `session_id`, while all laps within that session share it. Reliable for partitioning or join keys across derived tables. |
| `session_time` | DECIMAL(10,3) | Seconds elapsed in the session at the moment the car finished the lap. Display as `MM:SS.mmm` for readability if you surface it to humans. |
| `clock_time` | DECIMAL(10,3) | Wall-clock time of lap completion relative to the session start; mirrors IMSA’s “Hour” column in decimal seconds. Prefer formatting as `HH:MM:SS.mmm` in output. |
| `session_time_lap_number` | INTEGER | Virtual lap counter based on session timing. It increments whenever any car (usually the leader) completes another lap, so heavily delayed cars line up with the field’s current progress. |
| `car` | VARCHAR | Car number exactly as reported, including leading zeros (`'01'`, `'007'`). Keeping it textual avoids collisions between `01` and `1`. |
| `class` | VARCHAR | Competition class (`GTP`, `LMP2`, `GTD`, etc.). Derived from the lap feed. |
| `driver_name` | VARCHAR | Driver name for display and filtering. Prefers the entry list canonical name when available, otherwise falls back to the normalized lap CSV value. Use this for most queries. |
| `driver_id` | VARCHAR | Stable identifier for the driver across all sessions and name variations (e.g., "mathias beche_2025"). Use this for aggregating laps across spelling variants like "Mathias BECHE" vs "Mathias Beche". |
| `lap` | INTEGER | Lap counter within the session for this car. Pit-out laps count as lap 1 once the timing loop is crossed. |
| `lap_time` | DECIMAL(10,3) | Lap duration stored as decimal seconds. Render as `MM:SS.mmm` (or longer for multi-minute laps) when presenting to humans. |
| `lap_time_s1` | DECIMAL(10,3) | Sector 1 time in decimal seconds. Render as `MM:SS.mmm` when presenting to humans. |
| `lap_time_s2` | DECIMAL(10,3) | Sector 2 time in decimal seconds. Render as `MM:SS.mmm` when presenting to humans. |
| `lap_time_s3` | DECIMAL(10,3) | Sector 3 time in decimal seconds. Render as `MM:SS.mmm` when presenting to humans. |
| `lap_time_driver_rank` | BIGINT | Per-driver ranking of `lap_time` values within a session, with 1 representing that driver's fastest completed lap (NULL when the lap time is missing). |
| `pit_time` | DECIMAL(10,3) | Time stationary in pit lane for laps that include a service, expressed in decimal seconds (NULL when IMSA omits it). When reporting, convert to `MM:SS.mmm`. |
| `flags` | VARCHAR | Flag state at the finish line (examples: `GF` green flag, `FCY` full-course yellow). |
| `stint_start` | INTEGER | Indicator flag (1/0) that marks the first lap after a driver change for a car within the session. Computed by comparing `driver_name` to the prior lap for the same `session_id` and `car`. |
| `stint_number` | HUGEINT | Running count of stints for the car inside a session. It increments only when `stint_start` flips to 1, so each contiguous driver run gets a distinct number. |
| `stint_lap` | INTEGER | Zero-based lap index within the current stint for the car. Out laps and first laps display as 0. |
| `license` | VARCHAR | Driver license string (Platinum/Gold/Silver/Bronze) pulled from the exact session entry; remains NULL only when IMSA omits it in both the lap and results files. |
| `license_rank` | INTEGER | Numeric rank derived from `license` (5 = Platinum … 2 = Bronze, 0 = unknown). Handy for numeric comparisons or filters. |
| `driver_country` | VARCHAR | Country code for the driver, sourced from the entry list. |
| `team_name` | VARCHAR | Final team attribution. Prefers the entry list team, falls back to the lap CSV label, ensuring that driver swaps never drag the car into a different team. |
| `air_temp_f` | DECIMAL(6,2) | Air temperature (°F) at lap completion, sourced from the most recent weather reading at or before `session_time`. |
| `track_temp_f` | DECIMAL(6,2) | Track surface temperature (°F) from the same aligned weather snapshot. |
| `humidity_percent` | DECIMAL(6,2) | Relative humidity percentage associated with the lap. |
| `pressure_inhg` | DECIMAL(6,2) | Atmospheric pressure (inHg) aligned with the lap. |
| `wind_speed_mph` | DECIMAL(6,2) | Wind speed (mph) from the aligned weather record. |
| `wind_direction_degrees` | INTEGER | Wind direction in degrees from true north. |
| `raining` | BOOLEAN | True when the matched weather reading indicates rain. |


## Usage Notes

- Treat `session_id` as the stable join key whenever you need to connect laps to
  other session-scoped tables (weather, results). It is unique per
  `(year, event, session, start_date)` and remains stable across re-runs.
- Car numbers are stored as strings; if you need numeric ordering, cast with
  `CAST(car AS INTEGER)` but keep in mind that `'01'` and `'1'` refer to
  different entries in IMSA’s universe.
- Remaining NULL licenses are true blanks from IMSA (269 laps at the time of
  writing). Consider coalescing with the `drivers` view if you need full
  coverage.
- `stint_lap` starts at 0 for the out lap of each stint, so pair it with
  `stint_number` when you need to isolate in/out laps or normalize programs by
  stint length.
- `session_time_lap_number` tracks the race leader’s progress; use it when you
  need to view laps in the order they happened on track rather than per-car
  counts (helpful for DNFs or long repairs).
- Season-specific views (`laps_2021` … `laps_2025`) are created automatically if
  you prefer querying a fixed year without adding your own `WHERE year =` filters.
- All timing metrics are stored as decimal seconds for math; when generating
  human-facing text or charts, reformat them to `MM:SS.mmm` (or
  `HH:MM:SS.mmm` for long clocks) to match standard racing notation.
- Weather columns are nullable. When IMSA skips a reading for several minutes,
  the latest available record is reused, so sudden jumps are deliberate and
  reflect new data, not misalignment.


### Time Formatting

The correct way to format time intervals for humans follows a format of `MM:SS.mmm` for (M)inutes, (S)econds, and (m)illiseconds. If the timespan is greater than 1 hour, then the format is `HH:MM:SS.mmm`.

Use the `format_time(t)` macro to format decimal seconds:

Examples:
- `format_time(117.099)` → `01:57.099`
- `format_time(80.638)` → `01:20.638`
- `format_time(4.074)` → `00:04.074`
- `format_time(3661.234)` → `01:01:01.234`

### Gap Formatting

When displaying time gaps (e.g., gap to fastest driver), use the `format_gap(t)` macro which always shows the sign and 3 decimal places:

Examples:
- `format_gap(4.323)` → `+4.323`
- `format_gap(-1.3)` → `-1.300`
- `format_gap(0.001)` → `+0.001`
- `format_gap(0.0)` → `+0.000`

<!--
2025-01-18: Updated format_time macro to handle DOUBLE precision values from AVG()
calculations without overflow. Added format_gap macro for consistent gap display.
-->