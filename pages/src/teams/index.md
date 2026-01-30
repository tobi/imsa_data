---
title: Teams
---

# Team Directory

Browse all teams across IMSA, WEC, ELMS, Asian Le Mans, and Le Mans Cup.

```js
const teams = FileAttachment("../data/teams.csv").csv({typed: true});
```

```js
const searchInput = Inputs.search(teams, {placeholder: "Search teams..."});
const searchValue = Generators.input(searchInput);
```

```js
const seriesFilter = Inputs.select(
  ["All", ...new Set(teams.map(t => t.last_series).filter(Boolean))],
  {value: "All", label: "Series"}
);
const selectedSeries = Generators.input(seriesFilter);
```

<div class="grid grid-cols-2" style="max-width: 600px;">
  <div>${searchInput}</div>
  <div>${seriesFilter}</div>
</div>

```js
const filteredTeams = searchValue.filter(t => {
  if (selectedSeries === "All") return true;
  return t.last_series === selectedSeries;
});
```

<div class="tip">Showing ${filteredTeams.length} of ${teams.length} teams</div>

```js
const table = Inputs.table(filteredTeams, {
  columns: [
    "team",
    "total_events",
    "unique_drivers",
    "total_laps",
    "last_class",
    "last_series",
    "first_year",
    "last_year"
  ],
  header: {
    team: "Team",
    total_events: "Events",
    unique_drivers: "Drivers",
    total_laps: "Total Laps",
    last_class: "Class",
    last_series: "Series",
    first_year: "First",
    last_year: "Last"
  },
  format: {
    team: d => htl.html`<a href="./[team]?team=${encodeURIComponent(d)}">${d}</a>`,
    total_laps: d => d ? d.toLocaleString() : "-"
  },
  sort: "total_events",
  reverse: true,
  width: {
    team: 250,
    total_events: 70,
    unique_drivers: 70,
    total_laps: 90,
    last_class: 80,
    last_series: 60,
    first_year: 50,
    last_year: 50
  },
  rows: 25
});
```

${table}

## Teams by Series

```js
const seriesCounts = d3.rollup(teams, v => v.length, d => d.last_series || "Unknown");
const seriesData = Array.from(seriesCounts, ([series, count]) => ({series, count}))
  .sort((a, b) => b.count - a.count);
```

```js
Plot.plot({
  width: 500,
  height: 200,
  marginLeft: 80,
  x: {label: "Teams"},
  y: {label: null},
  marks: [
    Plot.barX(seriesData, {
      y: "series",
      x: "count",
      fill: "#457b9d",
      tip: true
    }),
    Plot.ruleX([0])
  ]
})
```

## Most Active Teams

Teams with the most event participations.

```js
const topTeams = teams.slice(0, 15);
```

```js
Plot.plot({
  width: 800,
  height: 400,
  marginLeft: 200,
  x: {label: "Events"},
  y: {label: null},
  marks: [
    Plot.barX(topTeams, {
      y: "team",
      x: "total_events",
      fill: "#2a9d8f",
      tip: true,
      title: d => `${d.team}\n${d.total_events} events\n${d.unique_drivers} drivers\n${d.total_laps.toLocaleString()} laps`
    }),
    Plot.ruleX([0])
  ]
})
```
