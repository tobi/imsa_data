# Import Notes and Workarounds

## Bot Protection Issue

As of October 2025, Al Kamel Systems websites have implemented bot protection that returns **403 Forbidden** errors for automated scraping:

```
HTTP/1.1 403 Forbidden
server: envoy
```

This affects all series:
- `fiawec.alkamelsystems.com` (WEC)
- `imsa.results.alkamelcloud.com` (IMSA)
- `elms.alkamelsystems.com` (ELMS)
- `alms.alkamelsystems.com` (Asian Le Mans)
- `lemanscup.alkamelsystems.com` (Le Mans Cup)

## Current Data Status

**IMSA:** ✅ Have 2021-2025 (1034 CSV files)
**WEC:** ❌ Need to acquire
**ELMS:** ❌ Need to acquire
**Asian Le Mans:** ❌ Need to acquire

## Alternative Import Methods

### Option 1: Manual Browser Download

1. Visit the timing website in your browser
2. Navigate to: Results → {Year} → {Event} → {Series} → {Session}
3. Look for CSV download links (typically named like `23_Analysis_Race.CSV`, `26_Weather_Race.CSV`, `03_Results_Race.CSV`)
4. Download and save to proper directory structure: `data/{series}/{year}/{event}/`

**Example for WEC 2024 Le Mans:**
```
Visit: http://fiawec.alkamelsystems.com/
→ Select: Season 13_2024
→ Select: Event 04_LE MANS
→ Select: 602_FIA WEC
→ Select: Race session
→ Download: 23_Analysis_Race.CSV, 26_Weather_Race.CSV, 03_Results_Race.CSV
→ Save to: data/wec/2024/04-le-mans/
```

### Option 2: Browser Automation (Selenium/Playwright)

If you need to import large amounts of data, browser automation tools can bypass the bot protection:

```python
from selenium import webdriver
from selenium.webdriver.common.by import By
import time

driver = webdriver.Chrome()
driver.get('http://fiawec.alkamelsystems.com/Results/13_2024/')
# Navigate and download files
```

### Option 3: API Access (if available)

Contact Al Kamel Systems to inquire about:
- Official API access
- Data licensing for research purposes
- Bulk data export options

### Option 4: Third-Party Sources

Some racing data providers may offer Al Kamel Systems data:
- Racing Reference
- Motorsport.com databases
- Team/series partnerships

## Respecting Data Ownership

Per Al Kamel Systems terms:
> "Data on these sites is wholly owned by Al Kamel Systems S.L. Any attempt by 3rd parties to distribute and/or disseminate any data without their previous express consent will lead to legal action."

**Recommendations:**
1. Only download data for personal analysis
2. Don't redistribute downloaded data publicly
3. Consider contacting Al Kamel for research partnerships
4. Respect rate limiting if manual downloading

## Working with Existing Data

Even with limited data, the database provides powerful analysis:

```bash
# Build database with current IMSA data (2021-2025)
rake db:update

# Query what we have
duckdb output/imsa.duckdb "SELECT year, COUNT(*) as events FROM seasons GROUP BY year"
```

## Future Improvements

Potential solutions to explore:
1. **OAuth/API partnership** with Al Kamel Systems
2. **Academic research agreement** for data access
3. **Team partnerships** (teams often have access to timing data)
4. **Historical archives** (check if older data is available elsewhere)
5. **Web scraping service** that respects robots.txt and rate limits

## Testing the Multi-Series Schema

Even without new data imports, you can:
1. Test database build with IMSA 2021-2025
2. Verify class normalization works
3. Test series-specific views
4. Manually add a few WEC/ELMS files to test cross-series queries

## Status: Ready for Manual Import

The schema is ready for multi-series data! Just need to:
1. Manually download CSV files from timing websites
2. Place in correct directory: `data/{series}/{year}/{event}/`
3. Run `rake db:update`

The infrastructure is complete, we just need the data files.
