# Multi-Series Support Generalization Proposal

## Executive Summary

This proposal outlines the changes needed to generalize the IMSA data repository to support multiple endurance racing series: **IMSA WeatherTech**, **WEC (World Endurance Championship)**, **ELMS (European Le Mans Series)**, and **ALMS (Asian Le Mans Series)**.

All four series use **Al Kamel Systems** for timing and results, making data collection highly consistent and enabling a unified approach.

---

## 1. Data Source Research

### Available Series and URLs

All target series use Al Kamel Systems infrastructure with similar URL patterns:

| Series | Base URL | Notes |
|--------|----------|-------|
| **IMSA WeatherTech** | `https://imsa.results.alkamelcloud.com/Results/` | Currently supported |
| **WEC** | `http://fiawec.alkamelsystems.com/Results/` | FIA World Endurance Championship |
| **ELMS** | `https://elms.alkamelsystems.com/Results/` | European Le Mans Series |
| **ALMS** | `http://alms.alkamelsystems.com/Results/` | Asian Le Mans Series |

### URL Structure Pattern

All series follow a consistent pattern:
```
{base_url}/{season_id}/{event_number}_{EVENT_NAME}/{series_id}_{SERIES_NAME}/{timestamp}_{session_name}/{file_type}.CSV
```

**Example (WEC):**
```
http://fiawec.alkamelsystems.com/Results/13_2024/02_IMOLA/526_FIA%20WEC/202404201445_Qualifying%20LMGT3/23_Analysis_Qualifying_LMGT3.CSV
```

**Example (IMSA):**
```
https://imsa.results.alkamelcloud.com/Results/24_2024/01_Roar_Before_the_24/IMSA%20WeatherTech/202401260800_Race/23_Laps_Race.CSV
```

### CSV File Types

Consistent across all series:
- `03_*_Results.CSV` - Race results
- `23_*_Analysis.CSV` or `23_*_Laps.CSV` - Lap-by-lap timing
- `26_*_Weather.CSV` - Weather conditions

---

## 2. Series Field Schema Design

### Proposed Series Naming Convention

**Format:** `{series_code}-{year}`

| Series Code | Full Name | Example |
|-------------|-----------|---------|
| `imsa` | IMSA WeatherTech Championship | `imsa-2024` |
| `wec` | FIA World Endurance Championship | `wec-2024` |
| `elms` | European Le Mans Series | `elms-2023` |
| `alms` | Asian Le Mans Series | `alms-2024` |

### Additional Series Identifiers

Consider also storing:
- **series_full_name**: "FIA World Endurance Championship", "IMSA WeatherTech Championship", etc.
- **series_code**: "wec", "imsa", "elms", "alms"
- **series_year**: Combined as `series-year` for easy filtering

---

## 3. Required Database Schema Changes

### 3.1 Add Series Fields to All Tables

#### `event_laps` table
```sql
-- Add after line 4 in 002-event-laps.sql
SELECT
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/...', 1) as series_code,
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/...', 2) as year,
    series_code || '-' || year as series,
    ...
```

#### `laps` table (main analysis table)
Add as **early columns** (after line 5 in 004-laps.sql):
```sql
CREATE OR REPLACE TABLE laps AS
SELECT
    laps.series,           -- NEW: e.g., 'imsa-2024'
    laps.series_code,      -- NEW: e.g., 'imsa'
    laps.start_date,
    laps.year,
    laps.event,
    ...
```

### 3.2 Update `session_id` Generation

Current `session_id` uses: `DENSE_RANK() OVER (ORDER BY year, event, session, start_date)`

**Problem:** Sessions across different series could collide.

**Solution:** Include series in ranking:
```sql
DENSE_RANK() OVER (ORDER BY series_code, year, event, session, start_date) as session_id
```

### 3.3 Update Foreign Key Joins

All joins on `session_id` remain valid, but queries should prefer filtering by `series` first for performance:
```sql
WHERE series = 'wec-2024' AND session = 'race'
```

---

## 4. Data Ingestion Changes

### 4.1 Directory Structure

**Current:**
```
data/
├── 2024/
│   ├── 01-roar-before-the-24/
│   └── 02-twelve-hours-of-sebring/
```

**Proposed:**
```
data/
├── imsa/
│   ├── 2024/
│   │   ├── 01-roar-before-the-24/
│   │   └── 02-twelve-hours-of-sebring/
│   └── 2023/
├── wec/
│   ├── 2024/
│   │   ├── 01-qatar/
│   │   ├── 02-imola/
│   │   └── 03-spa-francorchamps/
├── elms/
│   └── 2024/
└── alms/
    └── 2024/
```

### 4.2 Series Configuration

Create a series registry in `import.rb`:

```ruby
SERIES_CONFIG = {
  'imsa' => {
    name: 'IMSA WeatherTech Championship',
    base_url: 'https://imsa.results.alkamelcloud.com/Results/',
    url_pattern: '%{year_prefix}_%{year}/',
    series_pattern: 'IMSA WeatherTech',
    year_prefix_format: ->(year) { year.to_s[-2..] }  # "24" for 2024
  },
  'wec' => {
    name: 'FIA World Endurance Championship',
    base_url: 'http://fiawec.alkamelsystems.com/Results/',
    url_pattern: '%{season_id}_%{year}/',
    series_pattern: 'FIA WEC',
    year_prefix_format: ->(year) { (year - 2011).to_s }  # "13" for 2024 (started 2012)
  },
  'elms' => {
    name: 'European Le Mans Series',
    base_url: 'https://elms.alkamelsystems.com/Results/',
    url_pattern: '%{season_id}_%{year}/',
    series_pattern: 'European Le Mans Series',
    year_prefix_format: ->(year) { (year - 2005).to_s }  # Started 2006
  },
  'alms' => {
    name: 'Asian Le Mans Series',
    base_url: 'http://alms.alkamelsystems.com/Results/',
    url_pattern: '%{season_id}_%{year}/',
    series_pattern: 'Asian Le Mans Series',
    year_prefix_format: ->(year) { (year - 2020).to_s }  # Adjust based on actual
  }
}
```

### 4.3 Updated Import Script

Modify `import.rb` to accept `--series` parameter:

```ruby
ruby import.rb --series wec --year 2024
ruby import.rb --series elms --year 2023
ruby import.rb --series imsa --year 2024  # Backward compatible
```

### 4.4 Bulk Import Rake Task

```ruby
desc "Import all series for a given year"
task :import_all, [:year] do |t, args|
  year = args[:year] || Date.today.year
  %w[imsa wec elms alms].each do |series|
    sh "ruby import.rb --series #{series} --year #{year}"
  end
end
```

---

## 5. Query and View Changes

### 5.1 Series-Specific Views

Replace year-based views with series+year views:

**Current:**
```sql
CREATE VIEW laps_2024 AS SELECT * FROM laps WHERE year = '2024';
```

**Proposed:**
```sql
CREATE VIEW laps_imsa_2024 AS SELECT * FROM laps WHERE series = 'imsa-2024';
CREATE VIEW laps_wec_2024 AS SELECT * FROM laps WHERE series = 'wec-2024';
CREATE VIEW laps_elms_2024 AS SELECT * FROM laps WHERE series = 'elms-2024';
```

### 5.2 Cross-Series Analysis Views

```sql
-- All endurance racing in 2024
CREATE VIEW laps_endurance_2024 AS
SELECT * FROM laps WHERE year = '2024';

-- All LMP2 across all series
CREATE VIEW laps_lmp2 AS
SELECT * FROM laps WHERE class = 'LMP2';
```

---

## 6. Additional Considerations for Generalization

### 6.1 Class Name Normalization

Different series use different class naming:

| IMSA | WEC | ELMS |
|------|-----|------|
| GTP | Hypercar | LMP2 |
| LMP2 | LMGT3 | LMP2 Pro/Am |
| GTD Pro | - | LMP3 |
| GTD | - | LMGT3 |

**Recommendation:**
- Keep original class names in `class_original` field
- Add `class_normalized` field for cross-series analysis
- Create mapping table or function

### 6.2 Race Format Differences

| Series | Typical Formats |
|--------|----------------|
| IMSA | 2h40m, 6h, 10h, 12h, 24h |
| WEC | 6h, 8h, 24h |
| ELMS | 4h |
| ALMS | 4h |

**Recommendation:**
- Add `race_duration` field (in minutes or as interval)
- Extract from session metadata or event name

### 6.3 Calendar and Event Metadata

Track additional event information:

```sql
CREATE TABLE events (
    series TEXT,
    year TEXT,
    event_name TEXT,
    circuit_name TEXT,
    country TEXT,
    start_date TIMESTAMP,
    race_distance_km DECIMAL,
    race_duration_minutes INTEGER,
    PRIMARY KEY (series, year, event_name)
);
```

### 6.4 Driver License System Differences

- **IMSA/WEC/ELMS**: Use FIA license system (Platinum, Gold, Silver, Bronze)
- Some series might have different grading systems
- **Recommendation:** Keep as-is, populate NULL if not applicable

### 6.5 Championship Points

Each series has different points systems:
- Store in separate `points_systems` table
- Link to series+year
- Enable championship standings calculation

### 6.6 Multi-Class Race Handling

Different series run different class combinations:
- Track which classes ran in which events
- Some WEC rounds are Hypercar-only
- IMSA always runs multi-class

### 6.7 Series-Specific Regulations

Track regulation differences:
- Stint length limits
- Driver time requirements
- Fuel/energy allowances

---

## 7. Migration Path

### Phase 1: Add Series Fields (Backward Compatible)
1. ✅ Add `series` and `series_code` fields to all tables
2. ✅ Default to `'imsa'` and auto-detect year
3. ✅ Update `session_id` generation
4. ✅ Keep existing file structure working

### Phase 2: Multi-Series Import
1. ✅ Update directory structure to `data/{series}/{year}/`
2. ✅ Add series configuration
3. ✅ Update import.rb with series support
4. ✅ Test with WEC data

### Phase 3: Enhanced Schema
1. Add class normalization
2. Add event metadata table
3. Add championship points tables
4. Create cross-series analysis views

### Phase 4: Documentation and Publishing
1. Update README with multi-series examples
2. Publish to Hugging Face with series breakdown
3. Update marimo skill for multi-series analysis

---

## 8. Example Queries After Generalization

```sql
-- Compare LMP2 performance across series in 2024
SELECT
    series,
    event,
    driver_name,
    MIN(lap_time) as best_lap,
    AVG(lap_time) as avg_lap
FROM laps
WHERE year = '2024'
  AND class IN ('LMP2', 'LMP2 Pro/Am')
  AND session = 'race'
GROUP BY series, event, driver_name
ORDER BY best_lap;

-- Find drivers competing in multiple series
SELECT
    driver_name,
    STRING_AGG(DISTINCT series ORDER BY series) as series_competed,
    COUNT(DISTINCT series) as num_series
FROM laps
WHERE year = '2024'
GROUP BY driver_name
HAVING COUNT(DISTINCT series) > 1
ORDER BY num_series DESC;

-- Weather impact across different series
SELECT
    series,
    raining,
    AVG(EXTRACT(EPOCH FROM lap_time)) as avg_lap_seconds,
    COUNT(*) as laps
FROM laps
WHERE session = 'race' AND lap_time IS NOT NULL
GROUP BY series, raining
ORDER BY series, raining;
```

---

## 9. Recommended Implementation Order

1. ✅ **Add series field to laps table** (this proposal focuses here first)
2. ✅ Update directory structure for multi-series
3. ✅ Generalize import.rb
4. ✅ Update SQL extraction to parse series from path
5. Add series-specific views
6. Test with WEC 2024 data
7. Add ELMS and ALMS
8. Document and publish

---

## 10. Open Questions

1. **Year format for multi-year seasons?**
   - Some series span calendar years (e.g., "2023-2024 Asian Le Mans Series")
   - Recommendation: Use primary year, add `season_span` field if needed

2. **How to handle series name changes over time?**
   - E.g., "IMSA WeatherTech SportsCar Championship" vs "IMSA WeatherTech Championship"
   - Recommendation: Use consistent series_code, track full name changes in metadata

3. **Should we merge with historical series?**
   - American Le Mans Series (pre-2014)
   - World Sportscar Championship
   - Recommendation: Separate series codes, enable in queries

4. **Sprint series support?**
   - IMSA Michelin Pilot Challenge
   - GT World Challenge
   - Recommendation: Same framework, different series codes

---

## Conclusion

The generalization to support WEC, ELMS, and ALMS is **highly feasible** due to shared Al Kamel Systems infrastructure. The main changes required are:

1. Add `series` field early in the laps table
2. Update directory structure to `data/{series}/{year}/`
3. Generalize import.rb with series configuration
4. Update session_id generation to include series
5. Create series-specific views

This will enable powerful cross-series analysis while maintaining backward compatibility with existing IMSA-focused queries.
