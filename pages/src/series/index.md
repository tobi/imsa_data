---
title: Seasons
toc: false
---

```js
import {pillFilter} from "../components/pill-filter.js";
```

```js
const seasons = await FileAttachment("../data/seasons.csv").csv({typed: true});
const eventStats = await FileAttachment("../data/event-stats.csv").csv({typed: true});
```

```js
// Group seasons by series with additional stats
const bySeries = d3.group(seasons, d => d.series_code);

// Series metadata
const seriesMeta = {
  imsa: { name: "IMSA WeatherTech SportsCar Championship", color: "#e63946", abbrev: "IMSA" },
  wec: { name: "FIA World Endurance Championship", color: "#2a9d8f", abbrev: "WEC" },
  elms: { name: "European Le Mans Series", color: "#457b9d", abbrev: "ELMS" },
  alms: { name: "Asian Le Mans Series", color: "#e9c46a", abbrev: "ALMS" },
  lmc: { name: "Le Mans Cup", color: "#9b5de5", abbrev: "LMC" }
};

// Get unique series from data
const seriesList = [...bySeries.keys()].sort();

// Summary stats
const totalSeasons = seasons.length;
const totalLaps = d3.sum(seasons, d => d.total_laps);
const totalEvents = d3.sum(seasons, d => d.events);
const yearRange = [d3.min(seasons, d => d.year), d3.max(seasons, d => d.year)];
```

<!-- Hero Section -->
```js
display(htl.html`<div class="hero">
  <h1 class="hero-title">Racing Seasons</h1>
  <p class="hero-subtitle">Browse complete season data across all endurance racing series</p>
</div>`);
```

```js
display(htl.html`<div class="hero-stats">
  <div class="hero-stat">
    <span class="hero-stat-value">${seriesList.length}</span>
    <span class="hero-stat-label">Series</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${totalSeasons}</span>
    <span class="hero-stat-label">Seasons</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${totalEvents}</span>
    <span class="hero-stat-label">Events</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${(totalLaps / 1e6).toFixed(1)}M</span>
    <span class="hero-stat-label">Laps</span>
  </div>
  <div class="hero-stat">
    <span class="hero-stat-value">${yearRange[0]}-${yearRange[1]}</span>
    <span class="hero-stat-label">Coverage</span>
  </div>
</div>`);
```

---

```js
const seriesFilter = view(pillFilter(["All", ...seriesList.map(s => s.toUpperCase())], {
  label: "Series",
  colors: Object.fromEntries(seriesList.map(s => [s.toUpperCase(), seriesMeta[s]?.color || "#666"]))
}));
```

```js
const filteredSeries = seriesFilter === "All"
  ? seriesList
  : seriesList.filter(s => s.toUpperCase() === seriesFilter);
```

```js
for (const seriesCode of filteredSeries) {
  const meta = seriesMeta[seriesCode] || { name: seriesCode.toUpperCase(), color: "#666", abbrev: seriesCode.toUpperCase() };
  const seriesSeasons = (bySeries.get(seriesCode) || []).sort((a, b) => b.year - a.year);
  const totalSeriesLaps = d3.sum(seriesSeasons, d => d.total_laps);
  const totalSeriesEvents = d3.sum(seriesSeasons, d => d.events);

  display(htl.html`
    <div class="series-block">
      <div class="series-header" style="--series-color: ${meta.color}">
        <div class="series-badge">${meta.abbrev}</div>
        <div class="series-title-group">
          <h2 class="series-title">${meta.name}</h2>
          <div class="series-summary">
            ${seriesSeasons.length} seasons · ${totalSeriesEvents} events · ${(totalSeriesLaps / 1e6).toFixed(1)}M laps
          </div>
        </div>
      </div>

      <div class="seasons-table">
        <div class="table-header">
          <span class="col-year">Year</span>
          <span class="col-events">Events</span>
          <span class="col-drivers">Drivers</span>
          <span class="col-laps">Laps</span>
          <span class="col-weather">Weather</span>
          <span class="col-action"></span>
        </div>
        ${seriesSeasons.map(season => {
          const seriesEvents = eventStats.filter(e => e.series_code === seriesCode && e.year === season.year);
          const wetRaces = seriesEvents.filter(e => e.had_rain).length;
          const dryRaces = seriesEvents.length - wetRaces;

          return htl.html`
            <a href="./${seriesCode}-${season.year}" class="table-row">
              <span class="col-year">
                <span class="year-value">${season.year}</span>
              </span>
              <span class="col-events">
                <span class="stat-primary">${season.events}</span>
                <span class="stat-secondary">races</span>
              </span>
              <span class="col-drivers">
                <span class="stat-primary">${season.drivers}</span>
                <span class="stat-secondary">drivers</span>
              </span>
              <span class="col-laps">
                <span class="stat-primary">${(season.total_laps / 1000).toFixed(0)}k</span>
                <span class="stat-secondary">laps</span>
              </span>
              <span class="col-weather">
                ${dryRaces > 0 ? htl.html`<span class="weather-chip dry" title="${dryRaces} dry races">☀ ${dryRaces}</span>` : ''}
                ${wetRaces > 0 ? htl.html`<span class="weather-chip wet" title="${wetRaces} wet races">🌧 ${wetRaces}</span>` : ''}
              </span>
              <span class="col-action">
                <span class="view-link">View →</span>
              </span>
            </a>
          `;
        })}
      </div>
    </div>
  `);
}
```

<style>
@import "../components/styles.css";

/* Hero Section */
.hero {
  text-align: center;
  padding: 2rem 1rem 1rem;
  margin: -1rem -1rem 0;
  background: linear-gradient(135deg, var(--theme-background) 0%, color-mix(in srgb, var(--theme-foreground-focus) 8%, var(--theme-background)) 100%);
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.hero-title {
  font-size: 2rem;
  font-weight: 700;
  margin: 0;
  background: linear-gradient(135deg, var(--theme-foreground) 0%, var(--theme-foreground-focus) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.hero-subtitle {
  font-size: 0.95rem;
  color: var(--theme-foreground-muted);
  margin: 0.5rem 0 0;
}

.hero-stats {
  display: flex;
  justify-content: center;
  gap: 2rem;
  flex-wrap: wrap;
  padding: 1rem;
  background: var(--theme-background-alt);
  margin: 0 -1rem;
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.hero-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 80px;
}

.hero-stat-value {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--theme-foreground-focus);
  line-height: 1.1;
}

.hero-stat-label {
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* Series Block */
.series-block {
  margin-bottom: 2rem;
}

.series-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background: var(--theme-background-alt);
  border-radius: 8px 8px 0 0;
  border-left: 4px solid var(--series-color);
}

.series-badge {
  font-size: 0.85rem;
  font-weight: 700;
  padding: 0.4rem 0.75rem;
  background: var(--series-color);
  color: white;
  border-radius: 4px;
  letter-spacing: 0.03em;
}

.series-title-group {
  flex: 1;
}

.series-title {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--theme-foreground);
}

.series-summary {
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
  margin-top: 0.2rem;
}

/* Seasons Table */
.seasons-table {
  border: 1px solid var(--theme-foreground-faintest);
  border-top: none;
  border-radius: 0 0 8px 8px;
  overflow: hidden;
}

.table-header {
  display: grid;
  grid-template-columns: 80px 100px 100px 100px 120px 1fr;
  gap: 0.5rem;
  padding: 0.6rem 1rem;
  background: color-mix(in srgb, var(--theme-background-alt) 50%, var(--theme-background));
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.table-row {
  display: grid;
  grid-template-columns: 80px 100px 100px 100px 120px 1fr;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  text-decoration: none;
  color: var(--theme-foreground);
  border-top: 1px solid var(--theme-foreground-faintest);
  transition: background 0.1s;
  align-items: center;
}

.table-row:hover {
  background: var(--theme-background-alt);
}

.table-row:hover .view-link {
  opacity: 1;
  color: var(--theme-foreground-focus);
}

.year-value {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--theme-foreground);
}

.stat-primary {
  font-size: 1rem;
  font-weight: 600;
  color: var(--theme-foreground);
}

.stat-secondary {
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
  margin-left: 0.25rem;
}

.col-weather {
  display: flex;
  gap: 0.5rem;
}

.weather-chip {
  font-size: 0.75rem;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
}

.weather-chip.dry {
  background: color-mix(in srgb, #e76f51 15%, transparent);
  color: #e76f51;
}

.weather-chip.wet {
  background: color-mix(in srgb, #457b9d 15%, transparent);
  color: #457b9d;
}

.view-link {
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
  opacity: 0;
  transition: opacity 0.15s, color 0.15s;
}

/* Responsive */
@media (max-width: 768px) {
  .hero-stats {
    gap: 1rem;
  }

  .hero-stat-value {
    font-size: 1.25rem;
  }

  .table-header {
    display: none;
  }

  .table-row {
    grid-template-columns: 60px 1fr;
    grid-template-rows: auto auto;
    gap: 0.25rem 0.75rem;
    padding: 0.875rem 1rem;
  }

  .col-year {
    grid-row: span 2;
    display: flex;
    align-items: center;
  }

  .col-events, .col-drivers, .col-laps {
    display: inline;
  }

  .col-events::after, .col-drivers::after {
    content: " · ";
    color: var(--theme-foreground-muted);
  }

  .stat-secondary {
    display: none;
  }

  .col-weather {
    grid-column: 2;
  }

  .col-action {
    display: none;
  }
}

@media (max-width: 480px) {
  .series-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .hero-title {
    font-size: 1.5rem;
  }
}
</style>
