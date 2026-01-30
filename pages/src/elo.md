---
title: Elo Ratings Dashboard
---

# Elo Ratings Dashboard

Driver performance ratings based on lap-by-lap comparisons within class. The Plackett-Luce rating model evaluates every lap as a head-to-head competition between drivers.

```js
import {eloChart, eloDistribution} from "./components/elo-chart.js";
import {statCard} from "./components/stat-card.js";
import {pillFilter} from "./components/pill-filter.js";
```

```js
const eloHistory = await FileAttachment("data/elo-history.csv").csv({typed: true});
```

```js
// Get latest Elo for each driver
const latestElo = new Map();
for (const row of eloHistory) {
  const existing = latestElo.get(row.driver);
  if (!existing || row.session_date > existing.session_date) {
    latestElo.set(row.driver, row);
  }
}
const currentRatings = Array.from(latestElo.values());

// License and class colors
const licenseColors = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51"
};

const classColors = {
  GTP: "#e63946",
  GTDPRO: "#f4a261",
  GTD: "#e9c46a",
  LMP2: "#457b9d",
  DPi: "#d62828"
};
```

```js
// Minimum laps filter
const minLaps = view(Inputs.range([0, 500], {
  value: 50,
  step: 10,
  label: "Minimum laps"
}));
```

```js
const qualifiedDrivers = currentRatings.filter(d => d.cumulative_laps >= minLaps);

// Get unique classes
const classCounts = d3.rollup(qualifiedDrivers, v => v.length, d => d.class);
const topClasses = [...classCounts.entries()]
  .filter(([cls]) => cls)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 5)
  .map(([cls]) => cls);
```

## Overview

<div class="card-grid">

```js
display(statCard({
  title: "Rated Drivers",
  value: qualifiedDrivers.length,
  subtitle: `min ${minLaps} laps`
}));
```

```js
const avgElo = qualifiedDrivers.length > 0
  ? Math.round(qualifiedDrivers.reduce((sum, d) => sum + d.elo, 0) / qualifiedDrivers.length)
  : 0;
display(statCard({
  title: "Average Elo",
  value: avgElo
}));
```

```js
const topElo = Math.max(...qualifiedDrivers.map(d => d.elo), 0);
display(statCard({
  title: "Highest Elo",
  value: topElo
}));
```

```js
const totalLaps = qualifiedDrivers.reduce((sum, d) => sum + d.cumulative_laps, 0);
display(statCard({
  title: "Total Laps",
  value: totalLaps.toLocaleString()
}));
```

</div>

## Rating Distribution

```js
const distLicenseFilter = view(pillFilter(["All", "Platinum", "Gold", "Silver", "Bronze"], {
  label: "License",
  colors: licenseColors
}));
```

```js
const filteredForDist = distLicenseFilter === "All"
  ? qualifiedDrivers
  : qualifiedDrivers.filter(d => d.license === distLicenseFilter);

display(eloDistribution(filteredForDist, {
  width: width,
  height: 350,
  byLicense: distLicenseFilter === "All"
}));
```

## Driver Rankings

```js
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
let filteredDrivers = qualifiedDrivers;
if (classFilter !== "All") {
  filteredDrivers = filteredDrivers.filter(d => d.class === classFilter);
}
if (licenseFilter !== "All") {
  filteredDrivers = filteredDrivers.filter(d => d.license === licenseFilter);
}

const sortedDrivers = [...filteredDrivers].sort((a, b) => b.elo - a.elo);
```

```js
display(htl.html`<div class="styled-table table-scroll">
  <table>
    <thead>
      <tr>
        <th class="num">#</th>
        <th>Driver</th>
        <th class="num">Elo</th>
        <th>License</th>
        <th>Class</th>
        <th class="num hide-mobile">Laps</th>
        <th class="hide-mobile">Last Event</th>
      </tr>
    </thead>
    <tbody>
      ${sortedDrivers.slice(0, 50).map((d, i) => htl.html`
        <tr>
          <td class="num rank-cell ${i < 3 ? `rank-${i + 1}` : ''}">${i + 1}</td>
          <td>
            <a href="./drivers/[driver]?driver=${encodeURIComponent(d.driver)}" class="table-link driver-link">${d.driver}</a>
          </td>
          <td class="num elo-cell">${d.elo}</td>
          <td>
            ${d.license
              ? htl.html`<span class="license-badge ${d.license.toLowerCase()}">${d.license}</span>`
              : '-'
            }
          </td>
          <td>${d.class || '-'}</td>
          <td class="num hide-mobile">${d.cumulative_laps?.toLocaleString() || '-'}</td>
          <td class="hide-mobile event-cell">${d.event || '-'}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>`);
```

${sortedDrivers.length > 50 ? htl.html`<div class="text-muted" style="margin-top: 0.5rem; font-size: 0.85rem;">Showing top 50 of ${sortedDrivers.length} drivers matching filters.</div>` : ''}

## Elo Progression Over Time

Compare Elo progression for selected drivers.

```js
const driverOptions = qualifiedDrivers
  .sort((a, b) => b.elo - a.elo)
  .slice(0, 50)
  .map(d => d.driver);

const selectedDrivers = view(Inputs.select(driverOptions, {
  label: "Select drivers",
  multiple: true,
  value: driverOptions.slice(0, 3)
}));
```

```js
const driverHistory = eloHistory.filter(d =>
  selectedDrivers.includes(d.driver) && d.elo
);

display(eloChart(driverHistory, {
  width: width,
  height: 450,
  drivers: selectedDrivers,
  showDelta: true,
  colorBy: "driver"
}));
```

## Recent Rating Changes

Significant rating changes (delta >= 10 points) from recent events.

```js
const recentChanges = eloHistory
  .filter(d => Math.abs(d.delta || 0) >= 10)
  .sort((a, b) => b.session_date.localeCompare(a.session_date))
  .slice(0, 30);

display(htl.html`<div class="styled-table">
  <table>
    <thead>
      <tr>
        <th>Driver</th>
        <th class="hide-mobile">Date</th>
        <th>Event</th>
        <th class="num">Elo</th>
        <th class="num">Change</th>
        <th class="num hide-mobile">Laps</th>
      </tr>
    </thead>
    <tbody>
      ${recentChanges.map(d => htl.html`
        <tr>
          <td>
            <a href="./drivers/[driver]?driver=${encodeURIComponent(d.driver)}" class="table-link driver-link">${d.driver}</a>
          </td>
          <td class="hide-mobile">${d.session_date?.slice(0, 10) || '-'}</td>
          <td class="event-cell">${d.event || '-'}</td>
          <td class="num">${d.elo}</td>
          <td class="num ${d.delta > 0 ? 'delta-positive' : 'delta-negative'}">${d.delta > 0 ? '+' : ''}${d.delta}</td>
          <td class="num hide-mobile">${d.laps || '-'}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>`);
```

---

<div class="small muted">
Ratings use the Plackett-Luce model, updated after each race lap. Base rating is 1500.
</div>

<style>
@import "./components/styles.css";

.rank-cell {
  font-weight: 700;
}

.rank-1 { color: #ffd700; }
.rank-2 { color: #c0c0c0; }
.rank-3 { color: #cd7f32; }

.elo-cell {
  font-weight: 600;
}

.event-cell {
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.delta-positive {
  color: #2a9d8f;
  font-weight: 600;
}

.delta-negative {
  color: #e63946;
  font-weight: 600;
}

.license-badge {
  display: inline-block;
  padding: 0.15rem 0.4rem;
  font-size: 0.65rem;
  font-weight: 600;
  border-radius: 3px;
  color: white;
  text-transform: uppercase;
}

.license-badge.platinum { background: #e63946; }
.license-badge.gold { background: #2a9d8f; }
.license-badge.silver { background: #457b9d; }
.license-badge.bronze { background: #e76f51; }

.text-muted {
  color: var(--theme-foreground-muted);
}

.small {
  font-size: 0.85rem;
}

.muted {
  color: var(--theme-foreground-muted);
}
</style>
