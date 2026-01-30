---
title: Seasons
toc: false
---

# Racing Seasons

Browse racing seasons across all series.

```js
const seasons = await FileAttachment("../data/seasons.csv").csv({typed: true});
const eventStats = await FileAttachment("../data/event-stats.csv").csv({typed: true});
```

```js
// Group seasons by series with additional stats
const bySeries = d3.group(seasons, d => d.series_code);

// Series metadata
const seriesMeta = {
  imsa: { name: "IMSA WeatherTech SportsCar Championship", color: "#e63946", icon: "🏁" },
  wec: { name: "FIA World Endurance Championship", color: "#2a9d8f", icon: "🌍" },
  elms: { name: "European Le Mans Series", color: "#457b9d", icon: "🇪🇺" },
  alms: { name: "Asian Le Mans Series", color: "#e9c46a", icon: "🌏" },
  lmc: { name: "Le Mans Cup", color: "#9b5de5", icon: "🏆" }
};

// Get unique series from data
const seriesList = [...bySeries.keys()].sort();
```

<div class="series-section-grid">

```js
for (const seriesCode of seriesList) {
  const meta = seriesMeta[seriesCode] || { name: seriesCode.toUpperCase(), color: "#666", icon: "🏎️" };
  const seriesSeasons = bySeries.get(seriesCode) || [];
  const totalLaps = d3.sum(seriesSeasons, d => d.total_laps);
  const totalEvents = d3.sum(seriesSeasons, d => d.events);
  const uniqueDrivers = d3.max(seriesSeasons, d => d.drivers);

  display(htl.html`
    <div class="series-section" style="--series-color: ${meta.color}">
      <div class="series-section-header">
        <span class="series-icon">${meta.icon}</span>
        <div class="series-info">
          <h2 class="series-name">${meta.name}</h2>
          <div class="series-meta">
            ${seriesSeasons.length} seasons · ${totalEvents} races · ${(totalLaps / 1e6).toFixed(1)}M laps
          </div>
        </div>
      </div>
      <div class="season-grid">
        ${seriesSeasons.sort((a, b) => b.year - a.year).map(season => {
          const seriesEvents = eventStats.filter(e => e.series_code === seriesCode && e.year === season.year);
          const wetRaces = seriesEvents.filter(e => e.had_rain).length;

          return htl.html`
            <a href="./${seriesCode}-${season.year}" class="season-card">
              <div class="season-year">${season.year}</div>
              <div class="season-stats">
                <div class="season-stat">
                  <span class="stat-value">${season.events}</span>
                  <span class="stat-label">Races</span>
                </div>
                <div class="season-stat">
                  <span class="stat-value">${season.drivers}</span>
                  <span class="stat-label">Drivers</span>
                </div>
                <div class="season-stat">
                  <span class="stat-value">${(season.total_laps / 1000).toFixed(0)}k</span>
                  <span class="stat-label">Laps</span>
                </div>
              </div>
              ${wetRaces > 0 ? htl.html`<div class="wet-badge">${wetRaces} wet</div>` : ''}
            </a>
          `;
        })}
      </div>
    </div>
  `);
}
```

</div>

<style>
.series-section-grid {
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

.series-section {
  background: var(--theme-background-alt);
  border-radius: 8px;
  padding: 1.25rem;
  border-left: 4px solid var(--series-color);
}

.series-section-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1rem;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.series-icon {
  font-size: 2rem;
}

.series-info {
  flex: 1;
}

.series-name {
  margin: 0;
  font-size: 1.25rem;
  font-weight: 600;
  color: var(--series-color);
}

.series-meta {
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
  margin-top: 0.25rem;
}

.season-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.75rem;
}

.season-card {
  display: block;
  background: var(--theme-background);
  border-radius: 6px;
  padding: 0.875rem;
  text-decoration: none;
  transition: transform 0.15s, box-shadow 0.15s;
  position: relative;
  border: 1px solid var(--theme-foreground-faintest);
}

.season-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  border-color: var(--series-color);
}

.season-year {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--theme-foreground);
  margin-bottom: 0.5rem;
}

.season-stats {
  display: flex;
  gap: 0.75rem;
}

.season-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.stat-value {
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--theme-foreground);
}

.stat-label {
  font-size: 0.65rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
}

.wet-badge {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  font-size: 0.6rem;
  background: #457b9d;
  color: white;
  padding: 0.15rem 0.35rem;
  border-radius: 3px;
}

@media (max-width: 768px) {
  .series-section-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .season-grid {
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  }
}
</style>
