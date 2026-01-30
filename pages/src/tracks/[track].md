---
title: Track Details
---

```js
import {statCard} from "../components/stat-card.js";
import {formatLapTime} from "../components/lap-chart.js";
import {getTrackImageUrl} from "../components/track-images.js";
```

```js
// Get track ID from URL parameter
const params = new URLSearchParams(window.location.search);
const trackId = decodeURIComponent(params.get("track") || "");
const trackStats = await FileAttachment("../data/track-stats.csv").csv({typed: true});
const trackEvents = await FileAttachment("../data/track-events.csv").csv({typed: true});
const trackRecords = await FileAttachment("../data/track-records.csv").csv({typed: true});
```

```js
const track = trackStats.find(t => t.track_id === trackId);
const events = trackEvents.filter(e => e.track_id === trackId);
const records = trackRecords.filter(r => r.track_id === trackId);
const trackImageUrl = await getTrackImageUrl(trackId);
```

# ${track?.track_official_name || trackId}

```js
display(htl.html`
<div class="track-header">
  <div class="track-layout">
    ${trackImageUrl
      ? htl.html`<img src="${trackImageUrl}" alt="${track?.track_official_name}" />`
      : htl.html`<div class="no-image">No track layout available</div>`}
  </div>
  <div class="track-details">
    <div class="track-meta">
      <div class="meta-item">
        <span class="meta-label">Country</span>
        <span class="meta-value">${track?.track_country || "Unknown"}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">Events</span>
        <span class="meta-value">${track?.event_count || 0}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">Years Active</span>
        <span class="meta-value">${track?.first_year} - ${track?.last_year}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">Series</span>
        <span class="meta-value">${track?.series_count || 0}</span>
      </div>
    </div>
  </div>
</div>
`);
```

## Weather Statistics

<div class="card-grid">

```js
display(statCard({
  title: "Avg Air Temp",
  value: track?.avg_air_temp_f ? track.avg_air_temp_f.toFixed(1) + "°F" : "-"
}));
```

```js
display(statCard({
  title: "Avg Track Temp",
  value: track?.avg_track_temp_f ? track.avg_track_temp_f.toFixed(1) + "°F" : "-"
}));
```

```js
display(statCard({
  title: "Avg Humidity",
  value: track?.avg_humidity_pct ? track.avg_humidity_pct.toFixed(0) + "%" : "-"
}));
```

```js
display(statCard({
  title: "Rain Events",
  value: `${track?.wet_events || 0} / ${track?.event_count || 0}`,
  subtitle: `${track?.rain_pct?.toFixed(1) || 0}%`
}));
```

</div>

## Full Course Yellow

<div class="card-grid">

```js
display(statCard({
  title: "FCY Rate",
  value: track?.fcy_pct ? track.fcy_pct.toFixed(2) + "%" : "-"
}));
```

```js
display(statCard({
  title: "FCY Laps",
  value: track?.fcy_laps?.toLocaleString() || "0"
}));
```

```js
display(statCard({
  title: "Total Race Laps",
  value: track?.total_laps?.toLocaleString() || "0"
}));
```

</div>

## Lap Records by Class

Best lap times recorded in race conditions (Q1-Q2 pace laps only, excludes first lap, pit laps, and caution laps).

```js
const sortedRecords = records.sort((a, b) => a.lap_time - b.lap_time);
display(Inputs.table(sortedRecords, {
  columns: ["class", "lap_time", "driver", "car", "series_code", "year"],
  header: {
    class: "Class",
    lap_time: "Best Lap",
    driver: "Driver",
    car: "Car",
    series_code: "Series",
    year: "Year"
  },
  format: {
    lap_time: d => formatLapTime(d),
    driver: d => htl.html`<a href="../drivers/[driver]?driver=${encodeURIComponent(d)}">${d}</a>`,
    series_code: d => d?.toUpperCase()
  }
}));
```

## Event History

All race events held at this circuit.

```js
const yearFilter = view(Inputs.select(["All", ...new Set(events.map(e => e.year))].sort((a, b) => {
  if (a === "All") return -1;
  if (b === "All") return 1;
  return b - a;
}), {label: "Year", value: "All"}));
```

```js
const filteredEvents = yearFilter === "All" ? events : events.filter(e => e.year == yearFilter);
```

```js
display(Inputs.table(filteredEvents, {
  columns: ["start_date", "series_code", "event_name", "race_type", "race_duration_minutes", "avg_air_temp_f", "had_rain"],
  header: {
    start_date: "Date",
    series_code: "Series",
    event_name: "Event",
    race_type: "Type",
    race_duration_minutes: "Duration",
    avg_air_temp_f: "Temp (F)",
    had_rain: "Rain"
  },
  format: {
    series_code: d => d?.toUpperCase(),
    race_duration_minutes: d => d ? `${d} min` : "-",
    avg_air_temp_f: d => d?.toFixed(1) || "-",
    had_rain: d => d ? "Yes" : "No"
  },
  sort: "start_date",
  reverse: true
}));
```

## Events by Year

```js
const eventsByYear = d3.rollups(
  events,
  v => ({
    count: v.length,
    series: [...new Set(v.map(e => e.series_code))].join(", "),
    hadRain: v.some(e => e.had_rain)
  }),
  d => d.year
).map(([year, data]) => ({year, ...data}))
 .sort((a, b) => b.year - a.year);

display(Inputs.table(eventsByYear, {
  columns: ["year", "count", "series", "hadRain"],
  header: {
    year: "Year",
    count: "Events",
    series: "Series",
    hadRain: "Had Rain"
  },
  format: {
    series: d => d?.toUpperCase(),
    hadRain: d => d ? "Yes" : "No"
  }
}));
```

---

[Back to Tracks](/tracks/)

<style>
.track-header {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
  margin: 1.5rem 0;
}

@media (max-width: 768px) {
  .track-header {
    grid-template-columns: 1fr;
  }
}

.track-layout {
  background: var(--theme-background-alt);
  border-radius: 8px;
  padding: 1rem;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 200px;
}

.track-layout img {
  max-width: 100%;
  max-height: 300px;
  object-fit: contain;
}

.no-image {
  color: var(--theme-foreground-muted);
  font-style: italic;
}

.track-details {
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.track-meta {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 1rem;
}

.meta-item {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.meta-label {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--theme-foreground-muted);
}

.meta-value {
  font-size: 1.1rem;
  font-weight: 600;
}

.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 1rem;
  margin: 1rem 0;
}
</style>
