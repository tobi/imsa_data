---
title: Team Detail
---

```js
import {formatLapTime} from "../components/lap-chart.js";
```

```js
// Get team name from URL parameter
const params = new URLSearchParams(window.location.search);
const teamParam = params.get("team") || "";
const teamName = decodeURIComponent(teamParam);
```

```js
const teams = FileAttachment("../data/teams.csv").csv({typed: true});
const teamEvents = FileAttachment("../data/team-events.csv").csv({typed: true});
const teamResults = FileAttachment("../data/team-results.csv").csv({typed: true});
```

```js
// Find the team record
const team = teams.find(t =>
  t.team?.toLowerCase() === teamName.toLowerCase()
);

const displayName = team?.team || teamName || "Unknown Team";
```

# ${displayName}

```js
if (!team) {
  display(htl.html`<div class="warning">Team not found: ${teamName}</div>`);
}
```

```js
// Get this team's events
const events = teamEvents.filter(e =>
  e.team?.toLowerCase() === teamName.toLowerCase()
).sort((a, b) => new Date(b.event_date) - new Date(a.event_date));

// Get this team's results
const results = teamResults.filter(r =>
  r.team?.toLowerCase() === teamName.toLowerCase()
).sort((a, b) => new Date(b.start_date) - new Date(a.start_date));

// Get unique drivers who raced for this team
const allDrivers = new Set();
for (const e of events) {
  if (e.drivers) {
    e.drivers.split(", ").forEach(d => allDrivers.add(d));
  }
}
const driverList = Array.from(allDrivers).sort();

// Calculate results stats
const totalWins = results.filter(r => r.is_win).length;
const totalPodiums = results.filter(r => r.is_podium).length;
const totalTop5 = results.filter(r => r.is_top5).length;
```

## Overview

<div class="grid grid-cols-4">
  <div class="card">
    <h3>Events</h3>
    <div class="big">${team?.total_events || events.length}</div>
  </div>
  <div class="card">
    <h3>Drivers</h3>
    <div class="big">${team?.unique_drivers || driverList.length}</div>
  </div>
  <div class="card">
    <h3>Total Laps</h3>
    <div class="big">${team?.total_laps?.toLocaleString() || "-"}</div>
  </div>
  <div class="card">
    <h3>Series</h3>
    <div class="big">${team?.series_count || "-"}</div>
  </div>
</div>

<div class="grid grid-cols-4">
  <div class="card">
    <h3>First Year</h3>
    <div class="big">${team?.first_year || "-"}</div>
  </div>
  <div class="card">
    <h3>Last Year</h3>
    <div class="big">${team?.last_year || "-"}</div>
  </div>
  <div class="card">
    <h3>Last Class</h3>
    <div class="big">${team?.last_class || "-"}</div>
  </div>
  <div class="card">
    <h3>Last Series</h3>
    <div class="big">${team?.last_series?.toUpperCase() || "-"}</div>
  </div>
</div>

<div class="grid grid-cols-3">
  <div class="card">
    <h3>Wins</h3>
    <div class="big" style="color: #e63946;">${totalWins}</div>
  </div>
  <div class="card">
    <h3>Podiums</h3>
    <div class="big" style="color: #2a9d8f;">${totalPodiums}</div>
  </div>
  <div class="card">
    <h3>Top 5</h3>
    <div class="big">${totalTop5}</div>
  </div>
</div>

## Team History Timeline

```js
// Build timeline data from events - group by year and series
const timelineData = events.map(e => ({
  date: new Date(e.event_date),
  year: e.year,
  event: e.event,
  series: e.series_code,
  class: e.class,
  car: e.car,
  chassis: e.chassis,
  drivers: e.drivers,
  laps: e.total_laps
})).sort((a, b) => a.date - b.date);
```

```js
if (timelineData.length > 0) {
  display(Plot.plot({
    width: 900,
    height: Math.max(150, [...new Set(timelineData.map(d => d.series + " " + d.class))].length * 30),
    marginLeft: 100,
    marginBottom: 40,
    x: {
      type: "time",
      label: "Date"
    },
    y: {
      label: "Series/Class",
      domain: [...new Set(timelineData.map(d => d.series + " " + d.class))]
    },
    color: {
      legend: true,
      domain: [...new Set(timelineData.map(d => d.series))]
    },
    marks: [
      Plot.dot(timelineData, {
        x: "date",
        y: d => d.series + " " + d.class,
        fill: "series",
        r: 5,
        tip: true,
        title: d => `${d.event}\n${d.series.toUpperCase()} ${d.class}\nCar #${d.car}\n${d.chassis || ""}\n${d.drivers}\n${d.laps} laps`
      })
    ]
  }));
} else {
  display(htl.html`<div class="note">No timeline data available.</div>`);
}
```

## Results

### Wins

```js
const wins = results.filter(r => r.is_win);
```

```js
if (wins.length > 0) {
  // Deduplicate by event (may have multiple hourly results for same race)
  const uniqueWins = Array.from(
    d3.group(wins, d => `${d.series_code}-${d.year}-${d.event}-${d.car}`),
    ([key, values]) => values[0]
  ).sort((a, b) => new Date(b.start_date) - new Date(a.start_date));

  display(Inputs.table(uniqueWins, {
    columns: ["year", "event", "series_code", "class", "car", "track"],
    header: {
      year: "Year",
      event: "Event",
      series_code: "Series",
      class: "Class",
      car: "Car #",
      track: "Track"
    },
    width: {
      year: 60,
      event: 150,
      series_code: 60,
      class: 100,
      car: 50,
      track: 180
    }
  }));
} else {
  display(htl.html`<div class="note">No wins recorded.</div>`);
}
```

### Other Podiums (P2, P3)

```js
const podiums = results.filter(r => r.is_podium && !r.is_win);
```

```js
if (podiums.length > 0) {
  // Deduplicate
  const uniquePodiums = Array.from(
    d3.group(podiums, d => `${d.series_code}-${d.year}-${d.event}-${d.car}-${d.position}`),
    ([key, values]) => values[0]
  ).sort((a, b) => new Date(b.start_date) - new Date(a.start_date));

  display(Inputs.table(uniquePodiums.slice(0, 20), {
    columns: ["year", "event", "series_code", "class", "position", "car", "track"],
    header: {
      year: "Year",
      event: "Event",
      series_code: "Series",
      class: "Class",
      position: "Pos",
      car: "Car #",
      track: "Track"
    },
    format: {
      position: d => htl.html`<span style="color: ${d === 2 ? '#c0c0c0' : '#cd7f32'}; font-weight: bold;">P${d}</span>`
    },
    width: {
      year: 60,
      event: 150,
      series_code: 60,
      class: 100,
      position: 40,
      car: 50,
      track: 150
    }
  }));
} else {
  display(htl.html`<div class="note">No other podiums recorded.</div>`);
}
```

## Drivers

All drivers who have raced for this team.

```js
// Build driver stats from events
const driverStats = new Map();

for (const e of events) {
  if (!e.drivers) continue;
  const drivers = e.drivers.split(", ");
  for (const driver of drivers) {
    if (!driverStats.has(driver)) {
      driverStats.set(driver, {
        name: driver,
        events: 0,
        years: new Set(),
        classes: new Set(),
        series: new Set()
      });
    }
    const stats = driverStats.get(driver);
    stats.events++;
    stats.years.add(e.year);
    if (e.class) stats.classes.add(e.class);
    if (e.series_code) stats.series.add(e.series_code);
  }
}

const driverTable = Array.from(driverStats.values())
  .map(d => ({
    name: d.name,
    events: d.events,
    years: d.years.size,
    first_year: Math.min(...d.years),
    last_year: Math.max(...d.years),
    classes: [...d.classes].join(", "),
    series: [...d.series].map(s => s.toUpperCase()).join(", ")
  }))
  .sort((a, b) => b.events - a.events);
```

```js
if (driverTable.length > 0) {
  display(Inputs.table(driverTable, {
    columns: ["name", "events", "years", "first_year", "last_year", "classes", "series"],
    header: {
      name: "Driver",
      events: "Events",
      years: "Seasons",
      first_year: "First",
      last_year: "Last",
      classes: "Classes",
      series: "Series"
    },
    format: {
      name: d => htl.html`<a href="../drivers/[driver]?driver=${encodeURIComponent(d)}">${d}</a>`
    },
    width: {
      name: 180,
      events: 60,
      years: 70,
      first_year: 50,
      last_year: 50,
      classes: 150,
      series: 100
    }
  }));
} else {
  display(htl.html`<div class="note">No driver data available.</div>`);
}
```

## Car Entries by Season

```js
// Group events by year and car
const carsByYear = d3.groups(events, d => d.year)
  .sort((a, b) => b[0] - a[0])
  .map(([year, yearEvents]) => {
    const cars = d3.groups(yearEvents, d => d.car)
      .map(([car, carEvents]) => ({
        car,
        class: carEvents[0].class,
        chassis: carEvents[0].chassis,
        manufacturer: carEvents[0].manufacturer,
        series: carEvents[0].series_code,
        events: carEvents.length,
        drivers: [...new Set(carEvents.flatMap(e => e.drivers?.split(", ") || []))].join(", ")
      }));
    return {year, cars};
  });
```

```js
for (const {year, cars} of carsByYear) {
  display(htl.html`<h3>${year}</h3>`);
  display(Inputs.table(cars, {
    columns: ["car", "series", "class", "chassis", "events", "drivers"],
    header: {
      car: "Car #",
      series: "Series",
      class: "Class",
      chassis: "Chassis",
      events: "Events",
      drivers: "Drivers"
    },
    format: {
      series: d => d?.toUpperCase() || "-"
    },
    width: {
      car: 50,
      series: 60,
      class: 100,
      chassis: 180,
      events: 60,
      drivers: 300
    }
  }));
}
```

## Recent Events

```js
Inputs.table(events.slice(0, 20), {
  columns: ["year", "event", "series_code", "class", "car", "chassis", "drivers", "total_laps"],
  header: {
    year: "Year",
    event: "Event",
    series_code: "Series",
    class: "Class",
    car: "Car #",
    chassis: "Chassis",
    drivers: "Drivers",
    total_laps: "Laps"
  },
  format: {
    series_code: d => d?.toUpperCase() || "-"
  },
  width: {
    year: 60,
    event: 120,
    series_code: 60,
    class: 80,
    car: 50,
    chassis: 150,
    drivers: 200,
    total_laps: 50
  }
})
```

<style>
.big {
  font-size: 1.5em;
  font-weight: bold;
}
</style>
