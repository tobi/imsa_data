---
title: Drivers
---

# Driver Directory

Browse all drivers across IMSA, WEC, ELMS, Asian Le Mans, and Le Mans Cup.

```js
import {pillFilter} from "../components/pill-filter.js";
```

```js
const drivers = await FileAttachment("../data/drivers.csv").csv({typed: true});
const eloHistory = await FileAttachment("../data/elo-history.csv").csv({typed: true});
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

// Merge Elo data into drivers
const driversWithElo = drivers.map(d => {
  const elo = latestElo.get(d.canonical_name);
  return {
    ...d,
    elo: elo?.elo || null,
    cumulative_laps: elo?.cumulative_laps || 0
  };
});

// License colors
const licenseColors = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51"
};
```

```js
const searchTerm = view(Inputs.text({placeholder: "Search drivers...", width: "100%"}));
```

```js
const licenseFilter = view(pillFilter(["All", "Platinum", "Gold", "Silver", "Bronze"], {
  label: "License",
  colors: licenseColors
}));
```

```js
// Filter drivers
let filteredDrivers = driversWithElo;

if (searchTerm) {
  const term = searchTerm.toLowerCase();
  filteredDrivers = filteredDrivers.filter(d =>
    d.canonical_name?.toLowerCase().includes(term) ||
    d.team?.toLowerCase().includes(term) ||
    d.country?.toLowerCase().includes(term)
  );
}

if (licenseFilter !== "All") {
  filteredDrivers = filteredDrivers.filter(d => d.license === licenseFilter);
}

// Sort by Elo (highest first), then by name
filteredDrivers = filteredDrivers.sort((a, b) => {
  if (a.elo && b.elo) return b.elo - a.elo;
  if (a.elo) return -1;
  if (b.elo) return 1;
  return a.canonical_name.localeCompare(b.canonical_name);
});
```

<div class="tip">Showing ${filteredDrivers.length} of ${driversWithElo.length} drivers</div>

```js
display(htl.html`<div class="styled-table table-scroll">
  <table>
    <thead>
      <tr>
        <th>Driver</th>
        <th>License</th>
        <th class="num">Elo</th>
        <th class="hide-mobile">Country</th>
        <th>Team</th>
        <th>Class</th>
        <th class="num hide-mobile">Laps</th>
      </tr>
    </thead>
    <tbody>
      ${filteredDrivers.slice(0, 100).map(d => htl.html`
        <tr>
          <td>
            <a href="./[driver]?driver=${encodeURIComponent(d.canonical_name)}" class="table-link driver-link">${d.canonical_name}</a>
          </td>
          <td>
            ${d.license
              ? htl.html`<span class="license-badge ${d.license.toLowerCase()}">${d.license}</span>`
              : htl.html`<span class="text-muted">-</span>`
            }
          </td>
          <td class="num">${d.elo || '-'}</td>
          <td class="hide-mobile">${d.country || '-'}</td>
          <td class="team-cell">${d.team || '-'}</td>
          <td>${d.last_class || '-'}</td>
          <td class="num hide-mobile">${d.cumulative_laps?.toLocaleString() || '-'}</td>
        </tr>
      `)}
    </tbody>
  </table>
</div>`);
```

${filteredDrivers.length > 100 ? htl.html`<div class="text-muted" style="margin-top: 0.5rem; font-size: 0.85rem;">Showing first 100 of ${filteredDrivers.length} results. Use search to narrow down.</div>` : ''}

## License Distribution

```js
const licenseCounts = d3.rollup(drivers, v => v.length, d => d.license || "Unknown");
const licenseData = Array.from(licenseCounts, ([license, count]) => ({license, count}))
  .sort((a, b) => {
    const order = ["Platinum", "Gold", "Silver", "Bronze", "Unknown"];
    return order.indexOf(a.license) - order.indexOf(b.license);
  });
```

```js
display(Plot.plot({
  width: 500,
  height: 200,
  marginLeft: 80,
  style: {background: "transparent"},
  x: {label: "Drivers", grid: true},
  y: {label: null},
  color: {
    domain: ["Platinum", "Gold", "Silver", "Bronze", "Unknown"],
    range: ["#e63946", "#2a9d8f", "#457b9d", "#e76f51", "#9b5de5"]
  },
  marks: [
    Plot.barX(licenseData, {
      y: "license",
      x: "count",
      fill: "license",
      tip: true
    }),
    Plot.text(licenseData, {
      y: "license",
      x: "count",
      text: d => d.count,
      dx: 10,
      fill: "currentColor"
    }),
    Plot.ruleX([0])
  ]
}));
```

<style>
@import "../components/styles.css";

.team-cell {
  max-width: 200px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.text-muted {
  color: var(--theme-foreground-muted);
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
</style>
