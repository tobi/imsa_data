# Race Pace Analysis Techniques - Research Document

This document summarizes professional race pace analysis methods used in F1, WEC, and IMSA motorsport series. These techniques inform our dashboard visualization approach.

---

## Critical Analysis Rules

> **These rules MUST be followed for all pace analysis in our system.**

### What You Can NEVER Do

1. **NEVER compare lap times across different events** - Track conditions, weather, and layouts vary too much
2. **NEVER compare lap times across different classes** - GTP, LMP2, GTD are completely different cars with 5-15+ second pace differences
3. **NEVER average raw lap times for pace analysis** - Traffic, FCY, pit laps corrupt averages

### What You CAN Do

- Compare drivers in the **SAME CLASS** at the **SAME EVENT**
- Use delta from class leader or car's own best for relative pace
- Stint-to-stint comparisons within same event
- Weather-adjusted comparisons (wet laps only compared to other wet laps)

### The bpillar_quartile Filter

**For representative pace analysis, always use:**
```sql
WHERE bpillar_quartile IN (1, 2)
```

This automatically excludes:
- First lap of race
- Pit in/out laps
- Full course yellow / safety car laps
- Traffic-affected laps
- Outlier slow laps

Quartiles 1 and 2 represent the fastest 50% of a car's laps, giving clean "race pace" data.

### Delta-Based Visualization

**Always show pace as DELTA from a reference**, not absolute times:
- Delta from class best lap
- Delta from car's own Q1 average (fastest quartile)
- Delta from stint average

This makes cross-event trend analysis meaningful (e.g., "Driver X was +0.3s off class pace at Daytona, +0.5s at Sebring").

---

## 1. Stint Analysis Methods

### Degradation Metrics

Two primary metrics are used to measure tire degradation:

1. **Cumulative Degradation**: The difference in lap time between the current lap and the first lap of the tire stint
2. **Progressive Degradation**: The difference in lap time between the current lap and the previous lap

### Analysis Approaches

**State-Space Modeling** (Academic/Professional)
- Lap times modeled as a function of fuel mass and latent tire pace
- Pit stops treated as state resets
- Compound-specific degradation rates tracked separately
- Source: [A State-Space Approach to Modeling Tire Degradation](https://arxiv.org/pdf/2512.00640)

**Weighted Average Method**
- Calculate average slope (lap time increase) for each driver per stint
- Weight by stint length: a 20-lap stint contributes more than a 5-lap stint
- Measure degradation as "seconds per 10 laps" for comparability
- Source: [F1 Pace Analysis](https://f1pace.com/p/2024-bahrain-gp-tire-degradation/)

**Machine Learning Approaches**
- XGBoost models can predict tire degradation within 1.7 laps accuracy
- Feature engineering includes 50+ tire performance indicators:
  - Temperature gradients
  - Pressure variations
  - Compound-specific degradation rates
  - Circuit-specific wear patterns
- Source: [F1 Tire Degradation Prediction](https://schilamkur.github.io/Predict-Tire-Deg/)

### Compound-Specific Findings

| Compound | Degradation Pattern | Predictability |
|----------|---------------------|----------------|
| Soft | Strongest, most consistent degradation | Most predictable |
| Medium | Significant degradation | Moderate |
| Hard | May stabilize or improve after initial wear | Less predictable |
| Intermediate | Can show negative degradation (times improve) | Variable |

### Degradation Curves

Strategists define degradation curves for each compound showing:
- Warm-up phase
- Optimal operating window
- Wear degradation phase
- Overheating risk zone

These curves feed into strategy simulations predicting race outcomes.

---

## 2. Fuel-Corrected Lap Times

### The Problem

Cars get faster as they burn fuel - approximately 3+ seconds faster from race start to finish in F1 with a full 110kg fuel load.

### Standard Correction Values

| Source | Correction Factor | Notes |
|--------|-------------------|-------|
| Ted Kravitz (BBC) | 0.035 sec/kg | General rule |
| Pat Symonds Paper | 0.036-0.037 sec/kg | Academic study |
| Benzing Analysis | 0.02-0.04 sec/kg | Circuit dependent |

**Circuit-Dependent Adjustments:**
- Low-speed circuits: ~0.04 sec/kg
- Medium-speed circuits: ~0.03 sec/kg
- High-speed circuits: ~0.02 sec/kg

### Calculation Formula

```
Fuel Corrected Lap Time = Actual Lap Time - (Fuel Penalty x Remaining Fuel Mass)
```

Where:
- Fuel penalty = ~0.03-0.035 sec/kg (adjust by circuit)
- Fuel consumption = ~2.5-2.8 kg/lap (varies by circuit, driving style, safety car)

### Example: Turkey GP

- Fuel consumption: 2.7 kg/lap
- Fuel penalty: 0.3 sec per 10 kg
- Total time penalty at race start: ~4.5 seconds vs race end

### Caveats

- Relationship is not strictly linear
- Affected by: tire loads, ride height changes, center of gravity
- Fuel burn rate varies by driver and lap (lift-and-coast vs pushing)
- Safety car laps use less fuel

Sources: [F1 Technical Forum](https://www.f1technical.net/forum/viewtopic.php?t=7982), [Fuel Correction Analysis](https://medium.com/@umakschually/fuel-correction-29ccd98ae62b)

---

## 3. Traffic Impact Analysis

### Dirty Air Effects

When following another car, downforce loss causes significant lap time penalties:

| Distance | Downforce Retained (2019) | Downforce Retained (2022 baseline) | Downforce Retained (2025) |
|----------|---------------------------|-----------------------------------|---------------------------|
| 1 car length (10m) | ~55% | ~85% | ~65% |
| 2 car lengths (20m) | ~65% | ~95% | ~80% |

A car can lose **up to 50% of downforce** in dirty air, leading to slower lap times and reduced grip.

Source: [The Race - F1 Dirty Air Data](https://www.the-race.com/formula-1/exclusive-new-data-f1-aero-losses-ruining-close-racing/)

### Quantifying Traffic Time Loss

**Drag vs Downforce Trade-off:**
- Clean air downforce: ~680 kg
- At 1 car length: ~390 kg downforce (but drag reduced to 184 kg, 68 HP needed)
- At half car length: drag 161 kg, 54 HP needed

**Observed Time Losses:**
- Hungary 2006 example: ~10 seconds lost over several laps when stuck behind battling lapped cars
- Following within 1 second of another car at Suzuka 2025 was "incredibly difficult"

### Detection Methods for Traffic Laps

**Gap-Based Weighting:**
- Laps with <0.5 sec gap to car ahead: weight near 0% (heavily obstructed)
- Laps with >3 sec gap: weight at 100% (clear air)
- Intermediate gaps: proportional weighting

**Practical Implementation:**
- Flag laps where gap to car ahead < threshold (1-2 seconds)
- Create separate analysis with and without traffic laps
- Source: [F1 By The Numbers](https://f1bythenumbers.com/2020-abu-dhabi-gp-race-pace/)

---

## 4. Strategy Analysis: Undercut/Overcut Detection

### Undercut Definition

Pitting **earlier** than competitor to gain advantage through:
1. Fresh tire grip advantage
2. Faster out-lap on new tires
3. Potentially gaining track position

**Key phases:** In-lap, pit stop execution, out-lap

### Overcut Definition

Staying out **longer** on worn tires, betting that:
1. Competitor struggles to get new tires up to temperature
2. Your committed in-lap on stable (worn) tires is faster than their cold out-lap

### Detection Patterns

**Undercut Indicators:**
- Driver A pits 1-3 laps before Driver B
- Driver A's out-lap significantly faster than Driver B's in-lap
- Position change occurs during pit stop phase

**Overcut Indicators:**
- Driver A stays out while Driver B pits
- Driver A's subsequent laps faster than expected (fresh tires warming up slowly for Driver B)
- Position maintained or gained despite pitting later

### Factors Affecting Strategy Success

| Factor | Favors Undercut | Favors Overcut |
|--------|-----------------|----------------|
| Tire warm-up | Fast warm-up | Slow warm-up |
| Degradation | High deg tracks | Low deg tracks |
| Track type | Good overtaking | Monaco-style (hard to pass) |
| Pit crew | Fast stops essential | Less critical |

### Data Points for Analysis

Teams capture 1,000+ data points per second, running over 2 million predictive simulations. Key inputs:
- DRS train positions (being stuck negates undercut)
- Rival tire state and pace
- Pit lane time delta
- Warm-up characteristics by compound

Sources: [GPFans Strategy Explained](https://www.gpfans.com/en/f1-news/1016512/f1-undercut-overcut-explained/), [Catapult Sports](https://www.catapult.com/blog/motorsports-race-strategy-undercut-overcut)

---

## 5. Weather Impact Analysis

### Wet vs Dry Lap Time Differences

**Typical Differential:**
- Full wet conditions: **8-12 seconds per lap** slower than dry
- British GP example: Pole time in wet was 10 seconds slower than fastest dry race lap (100s vs 90s)

### Tire Selection Thresholds

| Condition | Tire | Typical Pace Loss |
|-----------|------|-------------------|
| Dry | Slicks | Baseline |
| Damp/Drying | Intermediates | 3-6 seconds |
| Full wet | Wet tires | 8-12+ seconds |
| Wrong tire (slicks on wet) | N/A | Multiple seconds per lap, increasing |

### Temperature Effects

**Track Temperature:**
- Higher track temps = higher tire temps = more grip (within optimal window)
- Each compound has different ideal temperature windows:
  - Softer compounds (C5, C6): lower temps
  - Harder compounds: higher temps
  - Wet tires: lower optimal window

**Cold Conditions:**
- Reduced grip due to tires not reaching operating temperature
- Slower lap times
- More difficult warm-up phases

### Rain-Specific Considerations

- Racing line rubber washed away ("green" track)
- Reduced visibility
- Different optimal lines (avoiding standing water)
- Grip level varies across track surface

**Setup Adjustments:**
- Decrease on-throttle differential by 20-50% depending on rain intensity
- Higher diff values cause snap oversteer in wet

Sources: [Catapult - Track Surface Impact](https://www.catapult.com/blog/race-strategy-f1-track-surface), [Motorsport Engineer](https://motorsportengineer.net/how-weather-conditions-influence-performance-in-formula-1/)

---

## 6. Multiclass Racing: Class Differentials

### IMSA Class Performance Hierarchy

| Class | Typical Lap Time vs GTP | Power | Notes |
|-------|------------------------|-------|-------|
| GTP | Baseline | 643-697 HP | LMDh/Hypercar |
| LMP2 | +3-5 seconds | ~600 HP | Spec ORECA chassis |
| LMP3 | +8-10 seconds | ~450 HP | Entry-level prototype |
| GTD PRO | +10-15 seconds | ~500 HP | Factory GT3 |
| GTD | +10-15 seconds | ~500 HP | Customer GT3 |

**2023 Rolex 24 Example (Daytona):**
- GTP fastest lap: ~1:35.6
- LMP2 fastest lap: ~1:39.6 (+4 seconds)
- LMP3 fastest lap: ~1:43.5 (+8 seconds)
- GTD PRO fastest lap: ~1:45.5 (+10 seconds)

### WEC Class Structure

Similar hierarchy:
- Hypercar/GTP: fastest
- LMP2: ~5 seconds slower
- LMGT3: ~10-15 seconds slower

### Implications for Pace Analysis

**Class Traffic:**
- Prototype leaders regularly lap GT cars multiple times
- "Blue flag" situations create traffic analysis complexity
- Time lost varies by track layout (narrow vs wide circuits)

**Balance of Performance (BoP):**
- Classes use BoP to equalize cars within class
- Adjusts: power, weight, aerodynamics
- Affects pace analysis when BoP changes mid-season

### Endurance-Specific Factors

**Stint Duration (WEC):**
- Typical stint: 45-60 minutes (fuel window)
- Driver changes add strategic dimension
- Some teams run quadruple stints on tires (4+ fuel stops per tire set)

**Tire Strategy:**
- Teams may change only partial tire sets (e.g., right-side only)
- Double/triple stinting tires common in endurance
- Degradation curves differ from sprint races

Sources: [IMSA Class Guide](https://www.imsa.com/weathertech/discover/the-classes/), [Sportscar365](https://sportscar365.com/imsa/iwsc/double-stinting-tires-adds-variable-to-gtp-race-strategy/)

---

## 7. Data Cleaning and Lap Time Normalization

### IMSA-Specific: bpillar_quartile

Our database includes a pre-computed `bpillar_quartile` column that categorizes each lap:

| Quartile | Description | Use Case |
|----------|-------------|----------|
| 1 | Fastest 25% of car's laps | Best representative pace |
| 2 | Second fastest 25% | Good representative pace |
| 3 | Third quartile | Mixed - some traffic/conditions |
| 4 | Slowest 25% | Pit laps, FCY, traffic, lap 1 |

**Standard filter for pace analysis:**
```sql
WHERE bpillar_quartile IN (1, 2)
```

This is preferred over manual outlier detection as it's pre-computed and consistent.

### Laps to Exclude (General Methodology)

Before pace analysis, remove:
1. **Lap 1** - Start chaos, cold tires, dirty air
2. **Safety car / FCY laps** - Artificially slow
3. **In-laps** - Preparing for pit stop
4. **Out-laps** - Cold tires, pit lane exit
5. **Safety car restart laps** - Variable pace
6. **Red flag affected laps**

### Outlier Detection Methods (When bpillar_quartile unavailable)

**IQR Method:**
- Calculate Q1, Q3, IQR for lap times
- Remove laps outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR]
- Limitation: may remove legitimate slow laps (driver error, mechanical issue)

**Generalized ESD Method:**
- Statistical test for multiple outliers
- Tests at significance level (typically 5%)
- Can identify safety car laps when explicit data unavailable

### Cross-Event Comparison (Delta Method)

**Never compare absolute lap times across events.** Instead:

1. **Delta from Class Best:** `lap_time - MIN(lap_time) OVER (PARTITION BY event, class)`
2. **Delta from Car's Q1 Average:** Compare to car's own fastest quartile average
3. **Percentile within Class/Event:** Where does this lap rank within the event?

**Example Query Pattern:**
```sql
SELECT
    driver_name,
    lap_time,
    lap_time - class_best AS delta_to_class_best,
    lap_time - car_q1_avg AS delta_to_own_pace
FROM laps
WHERE bpillar_quartile IN (1, 2)
  AND class = 'GTP'
  AND event_id = 'daytona_2024'
```

### Recommended Workflow

```
1. Filter to specific event + class (NEVER cross-event raw comparison)
2. Apply bpillar_quartile IN (1, 2) filter
3. Calculate reference pace (class best, car Q1 average)
4. Compute deltas from reference
5. For cross-event trends: compare DELTAS, not absolute times
6. Account for weather if conditions varied
```

Source: [F1 By The Numbers Methodology](https://f1bythenumbers.com/2019-f1-season-all-the-laps/), [Autosport Forums](https://forums.autosport.com/topic/206970-estimating-race-pace-a-statistical-model/)

---

## 8. Key Data Sources

### F1 Data
- **FastF1 Python Library:** Lap-by-lap data, telemetry, tire info, weather
- **Official F1 Timing:** Live timing data during sessions
- **AWS F1 Insights:** Car performance analysis, tire performance

### IMSA/WEC Data
- **Official timing & scoring:** Lap times, positions, pit stops
- **Race broadcasts:** Sector times, stint information
- **Team press releases:** Strategy explanations, tire choices

### Tools & Platforms
- [TracingInsights](https://tracinginsights.com/) - F1 analytics
- [F1 Pace](https://f1pace.com/) - Degradation analysis
- [Catapult Sports](https://www.catapult.com/) - Professional strategy tools

---

## 9. Visualization Recommendations

Based on this research, recommended visualizations for our dashboard.

> **Key Principle:** Always show DELTA from reference, never raw lap times for comparisons.

### Stint Analysis
- Line chart: **delta from stint average** vs lap number (shows degradation)
- Trend line overlay showing degradation slope (seconds per 10 laps)
- Compare degradation rates between drivers in same class

### Pace Comparison (Single Event)
- Box plots: **delta from class best** distribution per driver
- Bar chart: average delta per driver (using bpillar_quartile 1-2 laps only)
- Scatter plot: lap time vs lap number with Q1/Q2 laps highlighted

### Cross-Event Trends (Delta Only)
- Line chart: **delta from class pace** across events for a driver/team
- Shows consistency: "Was +0.3s off at Daytona, +0.5s at Sebring"
- Never show absolute times on same axis for different events

### Traffic Analysis
- Highlight bpillar_quartile 3-4 laps on lap time chart
- Show lap time distribution: Q1-2 (clean) vs Q3-4 (affected)
- Position vs time chart showing class traffic encounters

### Strategy
- Pit stop timing visualization (within single event)
- Stint length comparison between competitors
- Position delta through pit windows

### Weather
- Separate wet and dry lap visualizations (NEVER on same scale)
- Flag weather-affected sessions clearly
- Show pace delta within weather condition only

### Anti-Patterns to Avoid
- Raw lap time comparison across events
- Mixing classes on same visualization
- Averaging all laps (use Q1-2 filter)
- Showing absolute times for cross-event analysis

---

*Document prepared for Motorsport DB Dashboard development*
*Research completed: January 2026*
