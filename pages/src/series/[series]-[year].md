---
title: ${series.toUpperCase()} ${year} Season
---

# ${series.toUpperCase()} ${year} Season

```js
const series = observable.params.series;
const year = parseInt(observable.params.year);
```

```js
const events = await FileAttachment("../data/events.csv").csv({typed: true});
const standings = await FileAttachment("../data/season-standings.csv").csv({typed: true});
```

```js
const seasonEvents = events.filter(d => d.series_code === series && d.year === year);
const seasonStandings = standings.filter(d => d.series_code === series && d.year === year);
```

```js
const seriesNames = {
  imsa: "IMSA WeatherTech SportsCar Championship",
  wec: "FIA World Endurance Championship",
  elms: "European Le Mans Series",
  alms: "Asian Le Mans Series"
};
```

<h2>${seriesNames[series] || series.toUpperCase()} - ${year}</h2>

## Season Overview

<div class="card-grid">

```js
display(html`
  <div class="stat-card">
    <h3>Events</h3>
    <div class="value">${seasonEvents.length}</div>
    <div class="subtitle">Championship rounds</div>
  </div>
`);
```

```js
const uniqueDrivers = new Set(seasonStandings.map(d => d.driver)).size;
display(html`
  <div class="stat-card">
    <h3>Drivers</h3>
    <div class="value">${uniqueDrivers}</div>
    <div class="subtitle">Competed in races</div>
  </div>
`);
```

```js
const totalLaps = d3.sum(seasonStandings, d => d.total_laps);
display(html`
  <div class="stat-card">
    <h3>Total Laps</h3>
    <div class="value">${d3.format(",")(totalLaps)}</div>
    <div class="subtitle">Race laps completed</div>
  </div>
`);
```

```js
const uniqueCars = d3.sum(seasonEvents, d => d.cars || 0);
display(html`
  <div class="stat-card">
    <h3>Entries</h3>
    <div class="value">${d3.format(",")(uniqueCars)}</div>
    <div class="subtitle">Total car entries</div>
  </div>
`);
```

</div>

## Events Calendar

```js
const sortedEvents = seasonEvents.sort((a, b) => new Date(a.start_date || a.event_date) - new Date(b.start_date || b.event_date));
```

<table class="driver-table">
  <thead>
    <tr>
      <th>Date</th>
      <th>Event</th>
      <th>Track</th>
      <th>Sessions</th>
    </tr>
  </thead>
  <tbody>

```js
for (const event of sortedEvents) {
  const dateStr = (event.start_date || event.event_date)
    ? new Date(event.start_date || event.event_date).toLocaleDateString('en-US', {month: 'short', day: 'numeric'})
    : '-';
  display(html`
    <tr>
      <td>${dateStr}</td>
      <td><strong><a href="../events/${event.event_id || ''}">${event.event_name || event.event}</a></strong></td>
      <td>${event.track || '-'}</td>
      <td>${event.session_count || event.sessions || '-'}</td>
    </tr>
  `);
}
```

  </tbody>
</table>

## Top Performers by Class

```js
// Group by class and get top 10 by laps
const byClass = d3.group(seasonStandings, d => d.class);
```

```js
for (const [className, drivers] of byClass) {
  if (!className) continue;
  const top10 = drivers.sort((a, b) => b.total_laps - a.total_laps).slice(0, 10);

  display(html`<h3>${className}</h3>`);
  display(html`
    <table class="driver-table">
      <thead>
        <tr>
          <th>#</th>
          <th>Driver</th>
          <th>License</th>
          <th>Events</th>
          <th>Laps</th>
          <th>Team(s)</th>
        </tr>
      </thead>
      <tbody>
        ${top10.map((d, i) => html`
          <tr>
            <td><span class="position ${i < 3 ? 'position-' + (i+1) : ''}">${i + 1}</span></td>
            <td><a href="../drivers/${encodeURIComponent(d.driver)}">${d.driver}</a></td>
            <td><span class="license-badge license-${(d.license || 'l').toLowerCase().charAt(0)}">${d.license || '?'}</span></td>
            <td>${d.events}</td>
            <td>${d3.format(",")(d.total_laps)}</td>
            <td>${d.teams}</td>
          </tr>
        `)}
      </tbody>
    </table>
  `);
}
```

## License Distribution

```js
const licenseCount = d3.rollup(seasonStandings, v => v.length, d => d.license || 'Unknown');
const licenseData = Array.from(licenseCount, ([license, count]) => ({license, count}))
  .sort((a, b) => b.count - a.count);
```

```js
import * as Plot from "npm:@observablehq/plot";

display(Plot.plot({
  marginLeft: 80,
  x: {label: "Number of Drivers"},
  y: {label: null},
  marks: [
    Plot.barX(licenseData, {
      y: "license",
      x: "count",
      fill: d => {
        const colors = {Platinum: "#e63946", Silver: "#457b9d", Gold: "#2a9d8f", Bronze: "#e76f51", Unknown: "#9b5de5"};
        return colors[d.license] || "#999";
      },
      tip: true
    }),
    Plot.ruleX([0])
  ]
}));
```

<style>
${await FileAttachment("../style.css").text()}
</style>
