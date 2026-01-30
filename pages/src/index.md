---
title: Motorsport DB
toc: false
---

```js
import {formatLapTime} from "./components/lap-chart.js";
import {pillFilter} from "./components/pill-filter.js";
```

```js
const eventStats = await FileAttachment("data/event-stats.csv").csv({typed: true});
const classStats = await FileAttachment("data/class-stats.csv").csv({typed: true});
const eloHistory = await FileAttachment("data/elo-history.csv").csv({typed: true});
```

```js
// Summary stats
const totalEvents = eventStats.length;
const totalLaps = d3.sum(eventStats, d => d.total_laps);
const totalDrivers = new Set(eloHistory.map(d => d.driver)).size;
const seriesList = [...new Set(eventStats.map(d => d.series_code))].sort();
const rainEvents = eventStats.filter(d => d.had_rain).length;
const trackCount = new Set(eventStats.map(d => d.track)).size;

// Recent events (last 8)
const recentEvents = eventStats
  .sort((a, b) => new Date(b.start_date) - new Date(a.start_date))
  .slice(0, 8);

// Get current ratings (latest entry per driver)
const latestByDriver = new Map();
for (const row of eloHistory) {
  const existing = latestByDriver.get(row.driver);
  if (!existing || new Date(row.session_date) > new Date(existing.session_date)) {
    latestByDriver.set(row.driver, row);
  }
}
const currentRatings = Array.from(latestByDriver.values())
  .filter(d => d.cumulative_laps >= 100);

// Series color mapping
const seriesColors = {
  imsa: "#e63946",
  wec: "#2a9d8f",
  elms: "#457b9d",
  alms: "#e9c46a",
  lmc: "#9b5de5"
};

// Class colors
const classColors = {
  GTP: "#e63946",
  GTDPRO: "#f4a261",
  GTD: "#e9c46a",
  GTLM: "#2a9d8f",
  DPi: "#d62828",
  LMP2: "#457b9d",
  LMP3: "#90be6d",
  HYPERCAR: "#e63946",
  LMGT3: "#e9c46a"
};

const licenseColors = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51"
};
```

<!-- Hero Section -->
```js
display(htl.html`<div class="hero">
  <div class="hero-content">
    <h1 class="hero-title">Motorsport DB</h1>
    <p class="hero-subtitle">Comprehensive endurance racing data across IMSA, WEC, ELMS, Asian Le Mans, and Le Mans Cup</p>
  </div>
</div>`);
```

```js
display(htl.html`<div class="hero-stats">
  <div class="hero-stat">
    <span class="hero-stat-value">${(totalLaps / 1e6).toFixed(1)}M</span>
    <span class="hero-stat-label">Laps Recorded</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${totalEvents}</span>
    <span class="hero-stat-label">Race Events</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${totalDrivers.toLocaleString()}</span>
    <span class="hero-stat-label">Drivers</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${trackCount}</span>
    <span class="hero-stat-label">Circuits</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${seriesList.length}</span>
    <span class="hero-stat-label">Series</span>
  </div>
</div>`);
```

---

## Browse by Series

```js
display(htl.html`<div class="series-cards">
  ${seriesList.map(series => {
    const seriesEvents = eventStats.filter(d => d.series_code === series);
    const years = [...new Set(seriesEvents.map(d => d.year))].sort((a, b) => b - a);
    const laps = d3.sum(seriesEvents, d => d.total_laps);
    const color = seriesColors[series] || "#666";
    return htl.html`
      <a href="./series/?series=${series}" class="series-card" style="--series-color: ${color}">
        <div class="series-card-header">
          <span class="series-code">${series.toUpperCase()}</span>
          <span class="series-badge">${seriesEvents.length} races</span>
        </div>
        <div class="series-card-stats">
          <span>${years[0]}${years.length > 1 ? ` - ${years[years.length - 1]}` : ''}</span>
          <span>${(laps / 1e6).toFixed(1)}M laps</span>
        </div>
      </a>
    `;
  })}
</div>`);
```

---

## Recent Races

```js
display(htl.html`<div class="recent-races">
  ${recentEvents.map(e => {
    const eventSlug = `${e.series_code}-${e.year}-${e.event_name.toLowerCase().replace(/\s+/g, '-')}`;
    const seriesColor = seriesColors[e.series_code] || "#666";
    return htl.html`
      <a href="./events/[event]?event=${encodeURIComponent(eventSlug)}" class="race-card">
        <div class="race-card-top" style="--series-color: ${seriesColor}">
          <span class="race-series">${e.series_code.toUpperCase()}</span>
          <span class="race-date">${new Date(e.start_date).toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}</span>
        </div>
        <div class="race-card-content">
          <h3 class="race-name">${e.event_name}</h3>
          <p class="race-track">${e.track}</p>
          <div class="race-badges">
            ${e.had_rain ? htl.html`<span class="badge badge-rain">Wet</span>` : ''}
            ${e.fcy_pct > 15 ? htl.html`<span class="badge badge-caution">${e.fcy_pct}% FCY</span>` : ''}
          </div>
          <div class="race-stats">
            <span>${e.cars} cars</span>
            <span>${e.total_laps?.toLocaleString()} laps</span>
            <span>${e.drivers} drivers</span>
          </div>
        </div>
      </a>
    `;
  })}
</div>
<div class="section-link">
  <a href="./events/">View all events</a>
</div>`);
```

---

## Top Rated Drivers

```js
// Get unique classes for filter (top classes by driver count)
const classCounts = d3.rollup(currentRatings, v => v.length, d => d.class);
const topClasses = [...classCounts.entries()]
  .filter(([cls]) => cls)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 5)
  .map(([cls]) => cls);

const classFilter = view(pillFilter(["All", ...topClasses], {
  label: "Class",
  colors: classColors
}));
```

```js
const licenseFilter = view(pillFilter(["All", "Platinum", "Gold", "Silver", "Bronze"], {
  label: "License",
  colors: licenseColors
}));
```

```js
// Filter drivers based on selection
const filteredRatings = currentRatings.filter(d => {
  const classMatch = classFilter === "All" || d.class === classFilter;
  const licenseMatch = licenseFilter === "All" || d.license === licenseFilter;
  return classMatch && licenseMatch;
});

const topDrivers = filteredRatings
  .sort((a, b) => b.elo - a.elo)
  .slice(0, 10);
```

```js
display(htl.html`<div class="leaderboard">
  <div class="leaderboard-header">
    <span class="leaderboard-rank">#</span>
    <span class="leaderboard-driver">Driver</span>
    <span class="leaderboard-elo">Elo</span>
    <span class="leaderboard-license">License</span>
    <span class="leaderboard-class">Class</span>
    <span class="leaderboard-laps">Laps</span>
  </div>
  ${topDrivers.length === 0
    ? htl.html`<div class="leaderboard-empty">No drivers match the selected filters</div>`
    : topDrivers.map((d, i) => htl.html`
      <a href="./drivers/[driver]?driver=${encodeURIComponent(d.driver)}" class="leaderboard-row">
        <span class="leaderboard-rank rank-${i + 1}">${i + 1}</span>
        <span class="leaderboard-driver">${d.driver}</span>
        <span class="leaderboard-elo">${d.elo}</span>
        <span class="leaderboard-license" style="color: ${licenseColors[d.license] || '#666'}">${d.license || '-'}</span>
        <span class="leaderboard-class">${d.class || '-'}</span>
        <span class="leaderboard-laps">${d.cumulative_laps?.toLocaleString()}</span>
      </a>
    `)}
</div>
<div class="section-link">
  <a href="./elo">Full Elo rankings</a>
</div>`);
```

---

<div class="grid grid-cols-2">
<div>

## Weather Insights

```js
const tempData = eventStats.filter(d => d.avg_temp_f > 0 && d.avg_temp_f < 120);
const weatherSummary = {
  dry: eventStats.filter(d => !d.had_rain).length,
  wet: rainEvents,
  avgTemp: d3.mean(tempData, d => d.avg_temp_f)
};

display(htl.html`<div class="weather-summary">
  <div class="weather-stat">
    <span class="weather-icon">&#9728;</span>
    <span class="weather-value">${weatherSummary.dry}</span>
    <span class="weather-label">Dry Races</span>
  </div>
  <div class="weather-stat">
    <span class="weather-icon">&#127783;</span>
    <span class="weather-value">${weatherSummary.wet}</span>
    <span class="weather-label">Wet Races</span>
  </div>
  <div class="weather-stat">
    <span class="weather-icon">&#127777;</span>
    <span class="weather-value">${Math.round(weatherSummary.avgTemp || 0)}F</span>
    <span class="weather-label">Avg Temp</span>
  </div>
</div>`);
```

```js
display(Plot.plot({
  width: 400,
  height: 180,
  marginLeft: 40,
  marginBottom: 35,
  style: {background: "transparent"},
  x: {label: "Temperature (F)", ticks: 5},
  y: {label: "Races", grid: true},
  marks: [
    Plot.rectY(tempData, Plot.binX(
      {y: "count"},
      {
        x: "avg_temp_f",
        fill: d => d.had_rain ? "#457b9d" : "#e76f51",
        thresholds: 10
      }
    )),
    Plot.ruleY([0])
  ]
}));
```

```js
display(htl.html`<div class="chart-legend">
  <span class="legend-item"><span class="legend-color" style="background: #e76f51"></span> Dry</span>
  <span class="legend-item"><span class="legend-color" style="background: #457b9d"></span> Wet</span>
</div>`);
```

</div>
<div>

## Data Coverage by Class

```js
const classLapCounts = d3.rollups(
  classStats,
  v => ({
    total_laps: d3.sum(v, d => d.total_laps),
    events: d3.sum(v, d => d.events),
    cars: d3.sum(v, d => d.cars)
  }),
  d => d.class
).map(([cls, stats]) => ({class: cls, ...stats}))
  .filter(d => d.total_laps > 0)
  .sort((a, b) => b.total_laps - a.total_laps);

display(Plot.plot({
  width: 400,
  height: 220,
  marginLeft: 70,
  marginRight: 50,
  marginBottom: 30,
  style: {background: "transparent"},
  x: {label: "Laps (thousands)", grid: true},
  y: {label: null},
  marks: [
    Plot.barX(classLapCounts.slice(0, 8), {
      y: "class",
      x: d => d.total_laps / 1000,
      fill: d => classColors[d.class] || "#666",
      tip: true,
      title: d => `${d.class}\n${d.total_laps.toLocaleString()} laps\n${d.events} events`
    }),
    Plot.text(classLapCounts.slice(0, 8), {
      y: "class",
      x: d => d.total_laps / 1000,
      text: d => `${(d.total_laps / 1000).toFixed(0)}k`,
      dx: 5,
      textAnchor: "start",
      fill: "currentColor",
      fontSize: 10
    }),
    Plot.ruleX([0])
  ]
}));
```

</div>
</div>

---

## Caution Analysis

Events with highest percentage of laps under full course yellow.

```js
const fcyData = eventStats
  .filter(d => d.fcy_pct !== null && d.fcy_pct > 0)
  .sort((a, b) => b.fcy_pct - a.fcy_pct)
  .slice(0, 12);

display(Plot.plot({
  width: width,
  height: 300,
  marginLeft: 200,
  marginRight: 50,
  style: {background: "transparent"},
  x: {label: "% Under Caution", domain: [0, Math.max(...fcyData.map(d => d.fcy_pct)) + 5], grid: true},
  y: {label: null},
  marks: [
    Plot.barX(fcyData, {
      y: d => `${d.event_name} (${d.series_code.toUpperCase()} ${d.year})`,
      x: "fcy_pct",
      fill: d => d.fcy_pct > 25 ? "#e63946" : d.fcy_pct > 15 ? "#e76f51" : "#2a9d8f",
      tip: true,
      title: d => `${d.event_name}\n${d.series_code.toUpperCase()} ${d.year}\n${d.track}\n${d.fcy_pct}% under caution`
    }),
    Plot.text(fcyData, {
      y: d => `${d.event_name} (${d.series_code.toUpperCase()} ${d.year})`,
      x: "fcy_pct",
      text: d => `${d.fcy_pct}%`,
      dx: 5,
      textAnchor: "start",
      fill: "currentColor",
      fontSize: 10
    }),
    Plot.ruleX([0])
  ]
}));
```

---

## Quick Navigation

```js
display(htl.html`<div class="nav-grid">
  <a href="./events/" class="nav-card">
    <div class="nav-icon">&#127937;</div>
    <h3>Events</h3>
    <p>Browse all races by season, series, and track</p>
  </a>
  <a href="./drivers/" class="nav-card">
    <div class="nav-icon">&#127942;</div>
    <h3>Drivers</h3>
    <p>Search driver profiles, stats, and history</p>
  </a>
  <a href="./elo" class="nav-card">
    <div class="nav-icon">&#128200;</div>
    <h3>Elo Rankings</h3>
    <p>Performance ratings and progression charts</p>
  </a>
  <a href="./compare" class="nav-card">
    <div class="nav-icon">&#8596;</div>
    <h3>Compare</h3>
    <p>Head-to-head driver and car comparisons</p>
  </a>
</div>`);
```

---

<div class="footer">
Data sourced from official timing systems for IMSA WeatherTech, WEC, ELMS, Asian Le Mans, and Le Mans Cup.
</div>

<style>
/* Import shared styles */
@import "./components/styles.css";

/* Hero Section */
.hero {
  text-align: center;
  padding: 2.5rem 1rem 1rem;
  margin: -1rem -1rem 0;
  background: linear-gradient(135deg, var(--theme-background) 0%, color-mix(in srgb, var(--theme-foreground-focus) 8%, var(--theme-background)) 100%);
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.hero-title {
  font-size: 2.5rem;
  font-weight: 700;
  margin: 0;
  background: linear-gradient(135deg, var(--theme-foreground) 0%, var(--theme-foreground-focus) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.hero-subtitle {
  font-size: 1rem;
  color: var(--theme-foreground-muted);
  margin: 0.5rem 0 0;
  max-width: 600px;
  margin-left: auto;
  margin-right: auto;
}

.hero-stats {
  display: flex;
  justify-content: center;
  gap: 2rem;
  flex-wrap: wrap;
  padding: 1.25rem 1rem;
  background: var(--theme-background-alt);
  margin: 0 -1rem;
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.hero-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 90px;
}

.hero-stat-value {
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--theme-foreground-focus);
  line-height: 1.1;
}

.hero-stat-label {
  font-size: 0.75rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* Series Cards */
.series-cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 0.75rem;
}

.series-card {
  display: block;
  padding: 0.875rem;
  background: var(--theme-background-alt);
  border-radius: 6px;
  text-decoration: none;
  border-left: 4px solid var(--series-color, #666);
  transition: transform 0.15s, box-shadow 0.15s;
}

.series-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.series-card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.4rem;
}

.series-code {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--series-color, var(--theme-foreground));
}

.series-badge {
  font-size: 0.65rem;
  padding: 0.15rem 0.4rem;
  background: var(--theme-foreground-faintest);
  border-radius: 8px;
  color: var(--theme-foreground-muted);
}

.series-card-stats {
  display: flex;
  justify-content: space-between;
  font-size: 0.75rem;
  color: var(--theme-foreground-muted);
}

/* Recent Races */
.recent-races {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 0.875rem;
}

.race-card {
  display: block;
  background: var(--theme-background-alt);
  border-radius: 6px;
  overflow: hidden;
  text-decoration: none;
  transition: transform 0.15s, box-shadow 0.15s;
}

.race-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.race-card-top {
  display: flex;
  justify-content: space-between;
  padding: 0.4rem 0.65rem;
  background: var(--series-color, #666);
  color: white;
  font-size: 0.7rem;
}

.race-series {
  font-weight: 600;
}

.race-card-content {
  padding: 0.65rem;
}

.race-name {
  margin: 0 0 0.2rem;
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--theme-foreground);
}

.race-track {
  margin: 0 0 0.4rem;
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
}

.race-badges {
  display: flex;
  gap: 0.4rem;
  margin-bottom: 0.4rem;
  min-height: 1.2rem;
}

.badge {
  font-size: 0.6rem;
  padding: 0.1rem 0.35rem;
  border-radius: 3px;
  font-weight: 500;
}

.badge-rain {
  background: #457b9d;
  color: white;
}

.badge-caution {
  background: #e76f51;
  color: white;
}

.race-stats {
  display: flex;
  gap: 0.875rem;
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
}

/* Leaderboard */
.leaderboard {
  border: 1px solid var(--theme-foreground-faintest);
  border-radius: 6px;
  overflow: hidden;
}

.leaderboard-header,
.leaderboard-row {
  display: grid;
  grid-template-columns: 36px 1fr 55px 70px 60px 70px;
  gap: 0.4rem;
  padding: 0.5rem 0.875rem;
  align-items: center;
}

.leaderboard-header {
  background: var(--theme-background-alt);
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.leaderboard-row {
  text-decoration: none;
  color: var(--theme-foreground);
  border-top: 1px solid var(--theme-foreground-faintest);
  transition: background 0.1s;
}

.leaderboard-row:nth-child(even) {
  background: color-mix(in srgb, var(--theme-background-alt) 50%, transparent);
}

.leaderboard-row:hover {
  background: var(--theme-background-alt);
}

.leaderboard-empty {
  padding: 1.5rem;
  text-align: center;
  color: var(--theme-foreground-muted);
  font-size: 0.85rem;
}

.leaderboard-rank {
  font-weight: 700;
  text-align: center;
}

.rank-1 { color: #ffd700; }
.rank-2 { color: #c0c0c0; }
.rank-3 { color: #cd7f32; }

.leaderboard-driver {
  font-weight: 500;
}

.leaderboard-elo {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.leaderboard-license {
  font-weight: 500;
  font-size: 0.8rem;
}

.leaderboard-class {
  font-size: 0.75rem;
  color: var(--theme-foreground-muted);
}

.leaderboard-laps {
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
  text-align: right;
}

/* Weather Summary */
.weather-summary {
  display: flex;
  gap: 1.25rem;
  margin-bottom: 0.875rem;
}

.weather-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.2rem;
}

.weather-icon {
  font-size: 1.25rem;
}

.weather-value {
  font-size: 1.15rem;
  font-weight: 600;
  color: var(--theme-foreground-focus);
}

.weather-label {
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
}

.chart-legend {
  display: flex;
  gap: 0.875rem;
  margin-top: 0.4rem;
  font-size: 0.75rem;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 0.3rem;
}

.legend-color {
  width: 10px;
  height: 10px;
  border-radius: 2px;
}

/* Navigation Grid */
.nav-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 0.875rem;
}

.nav-card {
  display: block;
  padding: 1.25rem;
  background: var(--theme-background-alt);
  border-radius: 6px;
  text-decoration: none;
  text-align: center;
  transition: transform 0.15s, box-shadow 0.15s;
  border: 1px solid var(--theme-foreground-faintest);
}

.nav-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  border-color: var(--theme-foreground-focus);
}

.nav-icon {
  font-size: 1.75rem;
  margin-bottom: 0.4rem;
}

.nav-card h3 {
  margin: 0 0 0.4rem;
  font-size: 1rem;
  color: var(--theme-foreground);
}

.nav-card p {
  margin: 0;
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
}

/* Section Link */
.section-link {
  margin-top: 0.875rem;
  text-align: right;
}

.section-link a {
  font-size: 0.85rem;
  color: var(--theme-foreground-focus);
  text-decoration: none;
}

.section-link a:hover {
  text-decoration: underline;
}

/* Footer */
.footer {
  text-align: center;
  padding: 1.5rem 1rem;
  color: var(--theme-foreground-muted);
  font-size: 0.8rem;
}

/* Responsive */
@media (max-width: 768px) {
  .hero-title {
    font-size: 1.75rem;
  }

  .hero-stats {
    gap: 0.875rem;
  }

  .hero-stat-value {
    font-size: 1.35rem;
  }

  .leaderboard-header,
  .leaderboard-row {
    grid-template-columns: 32px 1fr 50px 60px;
  }

  .leaderboard-class,
  .leaderboard-laps {
    display: none;
  }
}

@media (max-width: 480px) {
  .hero-stats {
    flex-direction: column;
    gap: 0.5rem;
  }

  .hero-stat {
    flex-direction: row;
    gap: 0.4rem;
  }

  .series-cards {
    grid-template-columns: 1fr;
  }
}
</style>
