---
title: Tracks
---

# Racing Circuits

Browse all circuits across IMSA, WEC, ELMS, Asian Le Mans, and Le Mans Cup.

```js
import {statCard} from "../components/stat-card.js";
import {trackImages, getTrackImageUrl} from "../components/track-images.js";
```

```js
const trackStats = await FileAttachment("../data/track-stats.csv").csv({typed: true});

// Pre-resolve all track image URLs
const trackImageUrls = {};
for (const [id, file] of Object.entries(trackImages)) {
  try {
    trackImageUrls[id] = await file.url();
  } catch (e) {
    trackImageUrls[id] = null;
  }
}
```

## Filters

```js
const countryOptions = ["All", ...new Set(trackStats.map(t => t.track_country).filter(Boolean))].sort();
const countryFilter = view(Inputs.select(countryOptions, {label: "Country", value: "All"}));
```

```js
let filteredTracks = trackStats;
if (countryFilter !== "All") {
  filteredTracks = filteredTracks.filter(t => t.track_country === countryFilter);
}
```

<div class="card-grid">

```js
display(statCard({
  title: "Circuits",
  value: filteredTracks.length
}));
```

```js
const countries = new Set(filteredTracks.map(t => t.track_country));
display(statCard({
  title: "Countries",
  value: countries.size
}));
```

```js
const totalEvents = d3.sum(filteredTracks, t => t.event_count);
display(statCard({
  title: "Total Events",
  value: totalEvents
}));
```

```js
const avgFcy = d3.mean(filteredTracks.filter(t => t.fcy_pct > 0), t => t.fcy_pct);
display(statCard({
  title: "Avg FCY Rate",
  value: avgFcy ? avgFcy.toFixed(1) + "%" : "-"
}));
```

</div>

## Circuit Directory

<div class="track-grid">

```js
display(htl.html`${filteredTracks.map(track => {
  const imgUrl = trackImageUrls[track.track_id];
  return htl.html`
  <a href="./[track]?track=${track.track_id}" class="track-card">
    <div class="track-image">
      ${imgUrl
        ? htl.html`<img src="${imgUrl}" alt="${track.track_official_name}" />`
        : htl.html`<div class="no-image">No layout</div>`}
    </div>
    <div class="track-info">
      <div class="track-name">${track.track_official_name}</div>
      <div class="track-country">${track.track_country}</div>
      <div class="track-stats">
        <span>${track.event_count} events</span>
        <span>${track.rain_pct}% rain</span>
        <span>${track.fcy_pct ? track.fcy_pct.toFixed(1) + '% FCY' : '-'}</span>
      </div>
    </div>
  </a>
`})}`);
```

</div>

## By Country

```js
const byCountry = d3.rollups(
  trackStats,
  v => ({
    count: v.length,
    events: d3.sum(v, d => d.event_count),
    avgRain: d3.mean(v, d => d.rain_pct)
  }),
  d => d.track_country
).map(([country, stats]) => ({country, ...stats}))
 .sort((a, b) => b.count - a.count);

display(Inputs.table(byCountry, {
  columns: ["country", "count", "events", "avgRain"],
  header: {
    country: "Country",
    count: "Circuits",
    events: "Events",
    avgRain: "Avg Rain %"
  },
  format: {
    avgRain: d => d?.toFixed(1) + "%" || "-"
  }
}));
```

## Weather Statistics

Tracks ranked by likelihood of rain.

```js
const wetTracks = trackStats
  .filter(t => t.event_count >= 3)
  .sort((a, b) => b.rain_pct - a.rain_pct);

display(Inputs.table(wetTracks, {
  columns: ["track_official_name", "track_country", "event_count", "wet_events", "rain_pct", "avg_air_temp_f"],
  header: {
    track_official_name: "Circuit",
    track_country: "Country",
    event_count: "Events",
    wet_events: "Wet Events",
    rain_pct: "Rain %",
    avg_air_temp_f: "Avg Temp (F)"
  },
  format: {
    rain_pct: d => d?.toFixed(1) + "%",
    avg_air_temp_f: d => d?.toFixed(1) || "-"
  }
}));
```

## Full Course Yellow Rates

Tracks with highest FCY percentages (based on race laps).

```js
const fcyTracks = trackStats
  .filter(t => t.total_laps > 1000)
  .sort((a, b) => b.fcy_pct - a.fcy_pct);

display(Inputs.table(fcyTracks, {
  columns: ["track_official_name", "track_country", "event_count", "fcy_laps", "total_laps", "fcy_pct"],
  header: {
    track_official_name: "Circuit",
    track_country: "Country",
    event_count: "Events",
    fcy_laps: "FCY Laps",
    total_laps: "Total Laps",
    fcy_pct: "FCY %"
  },
  format: {
    fcy_laps: d => d?.toLocaleString(),
    total_laps: d => d?.toLocaleString(),
    fcy_pct: d => d?.toFixed(2) + "%"
  }
}));
```

<style>
.track-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1rem;
  margin: 1rem 0;
}

.track-card {
  display: block;
  text-decoration: none;
  color: var(--theme-foreground);
  border: 1px solid var(--theme-foreground-faintest);
  border-radius: 8px;
  overflow: hidden;
  transition: transform 0.15s, box-shadow 0.15s;
}

.track-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.track-image {
  height: 140px;
  background: var(--theme-background-alt);
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.track-image img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}

.no-image {
  color: var(--theme-foreground-muted);
  font-size: 0.85rem;
  font-style: italic;
}

.track-info {
  padding: 0.75rem;
}

.track-name {
  font-weight: 600;
  font-size: 0.95rem;
  margin-bottom: 0.25rem;
}

.track-country {
  font-size: 0.8rem;
  color: var(--theme-foreground-muted);
  margin-bottom: 0.5rem;
}

.track-stats {
  display: flex;
  gap: 0.75rem;
  font-size: 0.75rem;
  color: var(--theme-foreground-muted);
}

.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 1rem;
  margin: 1rem 0;
}
</style>
