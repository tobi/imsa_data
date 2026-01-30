---
title: Events
---

# Race Events

Browse race events by season, series, and track.

```js
import {statCard} from "../components/stat-card.js";
import {pillFilter} from "../components/pill-filter.js";
```

```js
const events = await FileAttachment("../data/events.csv").csv({typed: true});
```

```js
// Series colors
const seriesColors = {
  imsa: "#e63946",
  wec: "#2a9d8f",
  elms: "#457b9d",
  alms: "#e9c46a",
  lmc: "#9b5de5"
};

// Get filter options
const seriesOptions = [...new Set(events.map(e => e.series_code))].sort();
const yearOptions = [...new Set(events.map(e => e.year))].sort((a, b) => b - a);
```

```js
const seriesFilter = view(pillFilter(["All", ...seriesOptions.map(s => s.toUpperCase())], {
  label: "Series",
  colors: Object.fromEntries(seriesOptions.map(s => [s.toUpperCase(), seriesColors[s]]))
}));
```

```js
const yearFilter = view(pillFilter(["All", ...yearOptions.slice(0, 6).map(String)], {
  label: "Year"
}));
```

```js
let filteredEvents = events;
if (seriesFilter !== "All") {
  filteredEvents = filteredEvents.filter(e => e.series_code.toUpperCase() === seriesFilter);
}
if (yearFilter !== "All") {
  filteredEvents = filteredEvents.filter(e => String(e.year) === yearFilter);
}

// Sort by date descending
filteredEvents = filteredEvents.sort((a, b) => new Date(b.start_date) - new Date(a.start_date));
```

<div class="card-grid">

```js
display(statCard({
  title: "Events",
  value: filteredEvents.length
}));
```

```js
const tracks = new Set(filteredEvents.map(e => e.track));
display(statCard({
  title: "Tracks",
  value: tracks.size
}));
```

```js
const rainEventsCount = filteredEvents.filter(e => e.had_rain).length;
const rainPct = filteredEvents.length > 0 ? ((rainEventsCount / filteredEvents.length) * 100).toFixed(0) : 0;
display(statCard({
  title: "Wet Races",
  value: rainEventsCount,
  subtitle: `${rainPct}%`
}));
```

</div>

## Event List

```js
display(htl.html`<div class="styled-table">
  <table>
    <thead>
      <tr>
        <th>Date</th>
        <th>Series</th>
        <th>Event</th>
        <th>Track</th>
        <th>Type</th>
        <th class="num hide-mobile">Duration</th>
        <th>Weather</th>
      </tr>
    </thead>
    <tbody>
      ${filteredEvents.map(e => {
        const eventSlug = `${e.series_code}-${e.year}-${e.event_name.toLowerCase().replace(/\s+/g, '-')}`;
        const seriesColor = seriesColors[e.series_code] || "#666";
        return htl.html`
          <tr>
            <td>${new Date(e.start_date).toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}</td>
            <td><span class="series-badge" style="background: ${seriesColor}">${e.series_code.toUpperCase()}</span></td>
            <td><a href="./[event]?event=${encodeURIComponent(eventSlug)}" class="table-link event-link">${e.event_name}</a></td>
            <td class="track-link">${e.track}</td>
            <td>${e.race_type || '-'}</td>
            <td class="num hide-mobile">${e.race_duration_minutes ? `${e.race_duration_minutes} min` : '-'}</td>
            <td>${e.had_rain ? htl.html`<span class="badge-rain">Wet</span>` : 'Dry'}</td>
          </tr>
        `;
      })}
    </tbody>
  </table>
</div>`);
```

## By Track

```js
const byTrack = d3.rollups(
  filteredEvents,
  v => ({
    count: v.length,
    avgTemp: d3.mean(v, d => d.avg_air_temp_f),
    rainPct: d3.mean(v, d => d.had_rain ? 1 : 0) * 100,
    lastRace: d3.max(v, d => d.start_date)
  }),
  d => d.track
).map(([track, stats]) => ({track, ...stats}))
  .sort((a, b) => b.count - a.count);

display(htl.html`<div class="styled-table">
  <table>
    <thead>
      <tr>
        <th>Track</th>
        <th class="num">Events</th>
        <th class="num hide-mobile">Avg Temp (F)</th>
        <th class="num">Rain %</th>
        <th class="hide-mobile">Last Race</th>
      </tr>
    </thead>
    <tbody>
      ${byTrack.map(t => htl.html`
        <tr>
          <td class="track-link">${t.track}</td>
          <td class="num">${t.count}</td>
          <td class="num hide-mobile">${t.avgTemp?.toFixed(1) || '-'}</td>
          <td class="num">${t.rainPct?.toFixed(0)}%</td>
          <td class="hide-mobile">${t.lastRace ? new Date(t.lastRace).toLocaleDateString('en-US', {month: 'short', year: 'numeric'}) : '-'}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>`);
```

<style>
@import "../components/styles.css";

.badge-rain {
  display: inline-block;
  padding: 0.15rem 0.4rem;
  font-size: 0.7rem;
  font-weight: 500;
  border-radius: 3px;
  background: #457b9d;
  color: white;
}

.series-badge {
  display: inline-block;
  padding: 0.15rem 0.4rem;
  font-size: 0.65rem;
  font-weight: 600;
  border-radius: 3px;
  color: white;
  text-transform: uppercase;
}
</style>
