# Historical Data Availability Research

## Summary of Available Data by Series

Based on research of Al Kamel Systems timing platforms and partnership history, here's the estimated data availability:

| Series | First Year Available | Latest Year | Approx. Years | Data Source |
|--------|---------------------|-------------|---------------|-------------|
| **WEC** | 2012 | 2025 | **14 years** | fiawec.alkamelsystems.com |
| **IMSA** | 2016-2018* | 2025 | **8-10 years** | imsa.results.alkamelcloud.com |
| **ELMS** | Unknown (~2021?) | 2025 | **~5 years** | elms.alkamelsystems.com |
| **Asian Le Mans** | 2021 | 2024 | **4 years** | alms.alkamelsystems.com |
| **Le Mans Cup** | Unknown | 2025 | **Unknown** | lemanscup.alkamelsystems.com |

*IMSA: Al Kamel Systems partnership began in 2016, full implementation in 2017. Earlier data (2014-2015) may or may not be available.

## Detailed Findings by Series

### 1. FIA World Endurance Championship (WEC)

**Partnership History:**
- Al Kamel Systems has worked with WEC **since the championship began in 2012**
- Provides timing and IT services for the entire championship history

**Available Years:** 2012-2025 (potentially **14 years** of data)

**Data Evidence:**
- Search results confirmed seasons: 2011 (pre-season?), 2012, 2013, 2014
- URL pattern suggests continuous coverage: `fiawec.alkamelsystems.com/Results/{season_id}_{year}/`
- Season IDs follow formula: `(year - 2011)_year`
  - 2012 = `01_2012`
  - 2024 = `13_2024`
  - 2025 = `14_2025`

**Notable Events Included:**
- 24 Hours of Le Mans (every year 2012-2025)
- Spa 6 Hours, Silverstone, Bahrain 8 Hours, etc.

**Recommendation:** **Start with 2012 and import all 14 years** - This is the most complete dataset.

### 2. IMSA WeatherTech Championship

**Partnership History:**
- Al Kamel Systems became official timing partner in **2016**
- Full implementation rolled out in **2017 season**
- Previous timing provider: Unknown (2014-2015)

**Available Years:** Likely 2016-2025, possibly 2014-2015 (**8-10 years**)

**Data Evidence:**
- Found results from: 2018, 2021, 2025
- URL pattern: `{year_short}_{year}/` (e.g., `21_2021`, `25_2025`)
- Current repository has: 2021, 2022, 2023, 2024, 2025

**Uncertainty:**
- 2014-2015 may be available if Al Kamel archived pre-partnership data
- 2016-2020 should be available but not confirmed in search results

**Recommendation:** **Test import starting from 2014**, fall back to 2016-2017 if those years don't exist.

### 3. European Le Mans Series (ELMS)

**Partnership History:**
- Al Kamel Systems provides timing for ELMS (start date unclear)
- ELMS championship started in 2006

**Available Years:** Unknown, evidence of 2021-2025 (**~5 years** confirmed)

**Data Evidence:**
- Found 2021 qualifying data
- URL pattern suggests: `{season_id}_{year}/`
- Season ID calculation: `(year - 2005)_year`
  - 2021 = `16_2021`
  - 2024 = `19_2024`
  - 2025 = `20_2025`

**Uncertainty:**
- Unknown when Al Kamel became timing provider
- Could have significantly more years available

**Recommendation:** **Test import from 2015 onwards**, check how far back data exists.

### 4. Asian Le Mans Series

**Partnership History:**
- TimeService was timing provider until 2021
- **Al Kamel Systems took over in 2021**
- Series relaunched in 2013 (after original 2009-2011 run)

**Available Years:** 2021-2024 (**4 years** of data)

**Data Evidence:**
- Confirmed 2023-2024 season data
- Al Kamel only has data from 2021 onwards

**Recommendation:** **Import 2021-2024** (or current year).

### 5. Le Mans Cup

**Partnership History:**
- Part of ACO (Le Mans organizer) family
- Timing likely provided by Al Kamel Systems
- Series started around 2016

**Available Years:** Unknown

**Data Evidence:**
- Platform exists: lemanscup.alkamelsystems.com
- No specific years confirmed

**Recommendation:** **Test import from 2016-2020 onwards**.

## URL Pattern Analysis

All Al Kamel platforms follow similar structure:
```
{base_url}/Results/{season_id}_{year}/{event_number}_{EVENT}/...
```

**Season ID Formulas:**
- WEC: `(year - 2011)_year` → 2012=01_2012, 2024=13_2024
- IMSA: `{last_2_digits}_{year}` → 2024=24_2024
- ELMS: `(year - 2005)_year` → 2024=19_2024
- ALMS: `(year - 2020)_year` → 2024=04_2024 (estimated)
- LMC: Unknown (estimated `(year - 2015)_year`)

## Recommended Import Strategy

### Phase 1: Maximum Historical Coverage (WEC)
```bash
# WEC has the most historical data - 14 years!
for year in {2012..2025}; do
  ruby import.rb --series wec --year $year
done
```

**Expected data:** ~14 years × 8 races/year = **~112 events** with 24h Le Mans!

### Phase 2: IMSA Historical
```bash
# Try from 2014, fall back to 2016/2017 if needed
for year in {2014..2025}; do
  ruby import.rb --series imsa --year $year
done
```

**Expected data:** 8-10 years × 10-12 races/year = **~100-120 events**

### Phase 3: ELMS Exploration
```bash
# Test how far back ELMS data goes
for year in {2015..2025}; do
  ruby import.rb --series elms --year $year
done
```

**Estimated data:** 5-10 years × 6 races/year = **~30-60 events**

### Phase 4: Recent Series
```bash
# Asian Le Mans: 2021-2024
for year in {2021..2024}; do
  ruby import.rb --series alms --year $year
done

# Le Mans Cup: Test from 2016
for year in {2016..2025}; do
  ruby import.rb --series lmc --year $year
done
```

## Total Dataset Potential

**Conservative estimate:** ~250-300 events across all series
**Optimistic estimate:** ~400-500 events if older ELMS/IMSA data exists

**Database size estimate:**
- Laps per event: ~5,000-50,000 (sprint races vs 24h races)
- Average: ~15,000 laps/event
- Total: **3,750,000 to 7,500,000 lap records**

## Data Quality Notes

1. **24 Hours of Le Mans** data is especially valuable:
   - WEC 2012-2025: All 14 Le Mans races
   - Massive lap counts (300+ laps × 60+ cars = 18,000+ laps per race)

2. **Class evolution tracking:**
   - LMP1 era (2012-2020)
   - Hypercar era (2021-2025)
   - DPi era in IMSA (2017-2022)
   - GTP/LMDh convergence (2023+)

3. **Weather data:**
   - All Al Kamel platforms include weather CSVs
   - Enables climate analysis across circuits/years

4. **Driver tracking:**
   - Many drivers race in multiple series
   - Cross-series career analysis possible

## Recommended Next Steps

1. **Verify WEC 2012 availability** - This is the crown jewel dataset
2. **Test IMSA 2014** - Check if pre-partnership data exists
3. **Probe ELMS backwards from 2021** - Find the earliest year
4. **Create bulk import script** - Automate multi-year imports
5. **Add progress tracking** - Long imports need status monitoring

## Import Commands for Testing

```bash
# Test oldest WEC year (2012)
ruby import.rb --series wec --year 2012

# Test oldest likely IMSA year
ruby import.rb --series imsa --year 2014

# Test older ELMS years
ruby import.rb --series elms --year 2018
ruby import.rb --series elms --year 2015

# Import all Asian Le Mans
for year in 2021 2022 2023 2024; do
  ruby import.rb --series alms --year $year
done
```

## Year Prefix Calculations in import.rb

Current formulas in `import.rb`:
```ruby
'wec'  => ->(year) { "#{(year - 2011)}_#{year}" }  # ✓ Verified
'imsa' => ->(year) { "#{year.to_s[-2..]}_#{year}" }  # ✓ Verified
'elms' => ->(year) { "#{(year - 2005)}_#{year}" }  # Estimated
'alms' => ->(year) { "#{(year - 2020)}_#{year}" }  # Estimated
'lmc'  => ->(year) { "#{(year - 2015)}_#{year}" }  # Estimated
```

**To verify ELMS/ALMS/LMC formulas:**
1. Visit their respective websites
2. Check URL patterns for known years
3. Adjust formulas if needed

## Conclusion

The most exciting finding is **WEC's 14-year archive** including every 24 Hours of Le Mans since 2012. Combined with IMSA's substantial history, this could create one of the most comprehensive endurance racing databases ever assembled.

**Recommended first import:** WEC 2012-2025 for maximum historical value and complete Le Mans coverage.
