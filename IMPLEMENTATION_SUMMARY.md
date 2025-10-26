# Multi-Series Generalization - Implementation Summary

## Overview

This implementation adds **series field support** to the IMSA data repository, enabling it to support multiple endurance racing series: IMSA WeatherTech, WEC, ELMS, and Asian Le Mans Series.

## What Has Been Implemented

### 1. Series Fields Added to Database Schema

**New fields added early in all tables:**
- `series_code`: Short series identifier (e.g., "imsa", "wec", "elms", "alms")
- `series`: Combined series-year identifier (e.g., "imsa-2024", "wec-2024")

These fields appear as the **first two columns** in:
- `event_drivers` table
- `event_laps` table
- `event_weather` table
- `laps` table (main analysis table)
- `seasons` view

### 2. Backward Compatible Path Extraction

The SQL files now support **both** directory structures:

**Legacy (current):**
```
data/
├── 2024/
│   ├── 01-roar-before-the-24/
│   └── 02-twelve-hours-of-sebring/
```

**New multi-series:**
```
data/
├── imsa/
│   └── 2024/
│       ├── 01-roar-before-the-24/
│       └── 02-twelve-hours-of-sebring/
├── wec/
│   └── 2024/
│       ├── 01-qatar/
│       └── 02-imola/
```

**Default behavior:** Files in legacy structure (`data/year/...`) automatically get `series_code = 'imsa'`

### 3. Updated session_id Generation

**Before:**
```sql
DENSE_RANK() OVER (ORDER BY year, event, session, start_date)
```

**After:**
```sql
DENSE_RANK() OVER (ORDER BY series_code, year, event, session, start_date)
```

This ensures unique session IDs across all series.

### 4. Series-Specific Views Created

**New views in 005-season-views.sql:**

Series-only views (all sessions):
- `laps_imsa` - All IMSA data
- `laps_wec` - All WEC data
- `laps_elms` - All ELMS data
- `laps_alms` - All Asian Le Mans data

Series + Year views (race sessions only):
- `laps_imsa_2024`, `laps_imsa_2023`, etc.
- `laps_wec_2024`, `laps_wec_2025`
- `laps_elms_2024`, `laps_elms_2025`
- `laps_alms_2024`, `laps_alms_2025`

**Backward compatible views maintained:**
- `laps_2024`, `laps_2023`, etc. (shows all series for that year)

### 5. Enhanced Summary Statistics

The summary statistics in `004-laps.sql` now include:
- `series_count` - Number of different series in database
- `series_list` - Comma-separated list of series

Race summary now groups by `series, year` instead of just `year`.

### 6. Updated Foreign Key Joins

All joins now include `series_code` for proper matching:

```sql
LEFT JOIN event_drivers ed
    ON ed.series_code = ranked_stints.series_code
    AND ed.year = ranked_stints.year
    AND ed.event = ranked_stints.event
    ...
```

## Files Modified

1. **001-event-drivers.sql**
   - Added series extraction from filename
   - Added series_code and series to all CTEs
   - Updated joins to include series_code

2. **002-event-laps.sql**
   - Added series extraction from filename
   - Added series_code and series to all CTEs
   - Updated session_id generation
   - Updated joins to include series_code

3. **003-event-weather.sql**
   - Added series extraction from filename
   - Updated session_id generation to include series_code

4. **004-laps.sql**
   - Explicitly listed all columns with series_code and series first
   - Updated summary statistics to include series information
   - Updated race summary query to group by series

5. **005-season-views.sql**
   - Added series-specific views
   - Added series+year views
   - Maintained backward compatible year-only views
   - Updated seasons view to include series fields

## SQL Changes - Technical Details

### Filename Regex Pattern

**Legacy pattern:**
```regex
^data/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-(results|laps|weather)\.csv$
```

**New multi-series pattern:**
```regex
^data/([^/]+)/(\d{4})/\d\d\-([^/]+)/(\d+)\-([^/]+)\-(results|laps|weather)\.csv$
```

**Implementation using COALESCE:**
```sql
COALESCE(
    regexp_extract(filename, '^data/([^/]+)/(\d{4})/...', 1),
    'imsa'  -- default for legacy structure
) as series_code
```

### CSV Read Pattern Updates

All three CSV read operations now use dual patterns:

```sql
FROM read_csv(
    ["data/*/*/*laps.csv", "data/*/*/*/*laps.csv"],  -- Legacy + New
    union_by_name=true,
    filename=true,
    ...
)
```

## Usage Examples

### Query Specific Series

```sql
-- All IMSA 2024 race laps
SELECT * FROM laps WHERE series = 'imsa-2024' AND session = 'race';

-- Or use the view
SELECT * FROM laps_imsa_2024;

-- All WEC data
SELECT * FROM laps_wec;
```

### Cross-Series Analysis

```sql
-- Compare LMP2 performance across series
SELECT
    series,
    MIN(lap_time) as best_lap,
    AVG(lap_time) as avg_lap
FROM laps
WHERE class = 'LMP2' AND session = 'race'
GROUP BY series;

-- Drivers competing in multiple series
SELECT
    driver_name,
    STRING_AGG(DISTINCT series ORDER BY series) as series_competed
FROM laps
GROUP BY driver_name
HAVING COUNT(DISTINCT series_code) > 1;
```

### Series Filtering for Performance

```sql
-- Efficient series filtering (uses series field index)
SELECT * FROM laps WHERE series_code = 'wec' AND year = '2024';

-- Backward compatible (still works)
SELECT * FROM laps WHERE year = '2024';  -- All series
```

## Next Steps (Not Yet Implemented)

The following items from the proposal still need implementation:

### 1. Update import.rb for Multi-Series Support

```ruby
# Not yet implemented - see GENERALIZATION_PROPOSAL.md section 4.2
ruby import.rb --series wec --year 2024
```

Currently `import.rb` only supports IMSA. Needs:
- Series configuration hash with base URLs
- Series-specific year prefix calculation
- Output to `data/{series}/{year}/` structure

### 2. Additional Schema Enhancements

From the proposal, these remain pending:
- Class normalization table
- Race format/duration fields
- Event metadata table
- Championship points tables

### 3. Testing

- Test database build with existing IMSA data
- Validate series field defaults to 'imsa' correctly
- Test with multi-series data once importer is updated

## Validation Checklist

When testing the implementation:

- [ ] Existing IMSA data still loads correctly
- [ ] Series fields default to 'imsa' for legacy directory structure
- [ ] session_id remains unique across all data
- [ ] All views (legacy and new) work correctly
- [ ] Summary statistics include series information
- [ ] Cross-series joins work properly
- [ ] Can filter efficiently by series_code

## Migration Notes

### For Existing Users

**No action required!** The changes are backward compatible:
- Existing `data/year/...` structure continues to work
- All existing queries continue to work
- New `series` and `series_code` fields automatically populate with 'imsa'
- Legacy views (`laps_2024`, etc.) remain functional

### For Multi-Series Users

1. Organize data in new structure: `data/series/year/...`
2. Use updated `import.rb` (once implemented) with `--series` flag
3. Query using new series-specific views or filter by `series` field

## Performance Considerations

- **Series filtering**: Always include `series_code` or `series` in WHERE clauses for best performance
- **session_id**: Remains efficient for joins despite including series in generation
- **Views**: Series-specific views are lightweight (just WHERE clauses on main table)

## Documentation Impact

The following documentation needs updates:

1. **README.md**
   - Add section on multi-series support
   - Update example queries to show series filtering
   - Document new views

2. **Schema documentation**
   - Add series field descriptions
   - Update column order in examples

3. **Hugging Face dataset**
   - Update dataset description
   - Add series field to CSV exports

## Questions & Decisions Made

1. **Q: Should we create separate tables per series or use a unified table with series field?**
   - **A: Unified table with series field** - Easier to maintain, better for cross-series analysis, cleaner architecture

2. **Q: Should we break backward compatibility to clean up the structure?**
   - **A: No** - Support both legacy and new directory structures using COALESCE

3. **Q: Where should series fields appear in column order?**
   - **A: First two columns** - Makes them prominent and easy to filter/group by

4. **Q: Should year-only views show all series or just IMSA?**
   - **A: All series** - More flexible, users can filter if needed

## Related Documents

- **GENERALIZATION_PROPOSAL.md** - Full proposal with research and design
- See sections 3 (Schema Changes) and 5 (Views) for details on implementation
