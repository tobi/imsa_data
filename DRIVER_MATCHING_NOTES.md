# Driver Matching & License Tracking - Analysis

## Current Problems

### 1. WEC/ELMS Driver Data Not Imported
- IMSA results: `DRIVER1_FIRSTNAME`, `DRIVER1_SECONDNAME`, `DRIVER1_LICENSE`, etc.
- WEC/ELMS results: `DRIVER_1`, `DRIVER_2`, `DRIVER_3` (combined name, NO license)
- Current importer only handles IMSA format
- Result: `event_drivers` table has ONLY IMSA data

### 2. Name Variations Creating Duplicate IDs
Confirmed duplicates (same person, different IDs):
- `mathieu jaminet` / `matthieu jaminet`
- `giammaria bruni` / `gianmaria bruni`  
- `marvin kirchhofer` / `marvin kirchhöfer`
- `maxi buhk` / `maximilian buhk`
- `dan goldburg` / `daniel goldburg`
- `larry ten voorde` / `larry voorde`
- `alex riberas` / `alex riberas bou`
- `albert costa` / `albert costa balboa`

### 3. License is Time-Varying
- Current model: stores only "last license" in drivers table
- Reality: Licenses change frequently (42+ drivers had license changes 2021-2024)
- Examples:
  - mikkel jensen: Silver → Gold → Platinum (3 changes)
  - dane cameron: Gold → Platinum
  - kyle kirkwood: Silver → Gold
- Need: License per (driver, year, series)

### 4. Cross-Series ID Linking
- Same driver racing IMSA + WEC + ELMS should be one record
- Currently no linking mechanism
- WEC/ELMS have no `imsa_driver_id` equivalent

---

## Proposed Schema

```sql
-- Core driver identity
CREATE TABLE drivers (
    driver_id VARCHAR PRIMARY KEY,      -- canonical normalized name
    canonical_name VARCHAR,             -- display name (proper casing)
    country VARCHAR,
    first_seen DATE,
    last_seen DATE
);

-- Name aliases for fuzzy matching
CREATE TABLE driver_aliases (
    alias VARCHAR PRIMARY KEY,          -- normalized variant
    driver_id VARCHAR REFERENCES drivers,
    source VARCHAR,                     -- 'auto' | 'manual'
    confidence DECIMAL(3,2)             -- 0.0-1.0 for auto matches
);

-- External IDs (IMSA, FIA, etc.)
CREATE TABLE driver_external_ids (
    driver_id VARCHAR REFERENCES drivers,
    id_type VARCHAR,                    -- 'imsa_driver_id', 'fia_id', etc.
    external_id VARCHAR,
    PRIMARY KEY (driver_id, id_type)
);

-- License history (time-varying)
CREATE TABLE driver_licenses (
    driver_id VARCHAR REFERENCES drivers,
    year VARCHAR,
    series_code VARCHAR,                -- 'imsa', 'wec', 'elms'
    license VARCHAR,
    license_rank INTEGER,
    effective_date DATE,
    source_event VARCHAR,
    PRIMARY KEY (driver_id, year, series_code)
);

-- Team affiliations (time-varying)
CREATE TABLE driver_teams (
    driver_id VARCHAR REFERENCES drivers,
    year VARCHAR,
    series_code VARCHAR,
    team VARCHAR,
    car VARCHAR,
    class VARCHAR,
    PRIMARY KEY (driver_id, year, series_code, team)
);
```

---

## Implementation Steps

### Phase 1: Fix WEC/ELMS Import
1. Add WEC/ELMS column detection in `010-event-drivers.sql`
2. Parse `DRIVER_1`, `DRIVER_2`, `DRIVER_3` format
3. Note: No license data available in WEC/ELMS results

### Phase 2: Driver Alias System
1. Create `driver_aliases` table
2. Seed with known duplicates (manual file: `driver_aliases.json`)
3. Add fuzzy matching pass during import:
   - Jaro-Winkler > 0.92 → auto-alias with high confidence
   - 0.85-0.92 → flag for manual review

### Phase 3: License History
1. Create `driver_licenses` table
2. Modify event_drivers import to INSERT each (driver, year, series) license
3. For laps table, join on (driver_id, year, series_code) instead of just driver_id

### Phase 4: External ID Support  
1. Track IMSA driver IDs separately
2. Eventually add FIA IDs if available
3. Use external IDs for cross-series linking when names differ

---

## Open Questions

1. **Where to get WEC/ELMS license data?**
   - FIA publishes annual driver categorization lists
   - Could scrape/import as reference data
   - URL: https://www.fia.com/regulation/category/123

2. **Retroactive license data?**
   - Do we backfill Beche's Platinum status pre-2019?
   - Or accept gaps in historical data?

3. **Conflict resolution?**
   - If IMSA says Gold and WEC says Silver, which wins?
   - Probably store both, let queries choose

4. **Nickname handling?**
   - "Maxi Buhk" vs "Maximilian Buhk"
   - Auto-detect or require manual mapping?
