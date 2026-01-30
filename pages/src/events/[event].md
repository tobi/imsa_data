---
title: Event Details
---

```js
import {raceProgression, gapToLeader, pitStopTimeline} from "../components/race-progression.js";
import {lapTimeScatter, lapTimeLine, formatLapTime} from "../components/lap-chart.js";
import {statCard} from "../components/stat-card.js";
import {raceTimeline} from "../components/race-timeline.js";
```

```js
// Get event ID from URL parameter
const params = new URLSearchParams(window.location.search);
const eventId = decodeURIComponent(params.get("event") || "");
```

```js
const raceLaps = await FileAttachment("../data/race-laps.csv").csv({typed: true});
const events = await FileAttachment("../data/events.csv").csv({typed: true});
```

```js
// Parse event ID (format: SERIES-YEAR-EVENT_NAME)
// Example: imsa-2025-road-atlanta
const parts = eventId.split("-");
const series = parts[0];
const year = parseInt(parts[1]);
const eventSlug = parts.slice(2).join("-").toLowerCase();

// First find the event metadata by matching the slug against event_name
// The slug uses dashes where event_name has spaces
const eventMeta = events.find(e =>
  e.series_code === series &&
  e.year === year &&
  e.event_name?.toLowerCase().replace(/\s+/g, "-") === eventSlug
) || events.find(e =>
  // Fallback: partial match on event_name
  e.series_code === series &&
  e.year === year &&
  e.event_name?.toLowerCase().replace(/\s+/g, "-").includes(eventSlug.substring(0, 10))
) || {};

// The laps table uses 'event' = track name (normalized), not event_name
// So we need to match using the track from the event metadata
const trackName = eventMeta.track;

// Filter to this event's laps using the track name
const eventLaps = trackName
  ? raceLaps.filter(d =>
      d.series_code === series &&
      d.year === year &&
      d.event === trackName
    )
  : [];

// Page title
const pageTitle = eventMeta.event_name
  ? `${eventMeta.event_name} - ${eventMeta.series_code?.toUpperCase()} ${eventMeta.year}`
  : eventId;
```

# ${pageTitle}

## Event Overview

<div class="card-grid">

```js
display(statCard({
  title: "Track",
  value: eventMeta.track || "Unknown"
}));
```

```js
display(statCard({
  title: "Date",
  value: eventMeta.start_date || "Unknown"
}));
```

```js
const cars = new Set(eventLaps.map(d => d.car));
display(statCard({
  title: "Cars",
  value: cars.size
}));
```

```js
display(statCard({
  title: "Laps",
  value: eventLaps.length.toLocaleString()
}));
```

</div>

## Class Filter

```js
const classOptions = ["All", ...new Set(eventLaps.map(d => d.class).filter(Boolean))];
const classFilter = view(Inputs.select(classOptions, {label: "Class", value: "All"}));
```

```js
const filteredLaps = classFilter === "All"
  ? eventLaps
  : eventLaps.filter(d => d.class === classFilter);
```

## Race Timeline

Driver stints throughout the race. Boxes show each driver's stint colored by license (Platinum, Gold, Silver, Bronze). Yellow bands indicate Full Course Yellow periods. Vertical lines mark pit stops.

```js
if (filteredLaps.length > 0) {
  display(raceTimeline(filteredLaps, {
    width: Math.max(width, 1000),
    height: 500,
    filterClass: classFilter === "All" ? null : classFilter
  }));
} else {
  display(html`<p>No lap data available for this event.</p>`);
}
```

## Race Progression

Position changes throughout the race.

```js
if (filteredLaps.length > 0) {
  display(raceProgression(filteredLaps, {
    width: width,
    height: 500,
    byClass: classFilter !== "All"
  }));
} else {
  display(html`<p>No lap data available for this event.</p>`);
}
```

## Lap Times

```js
const carOptions = [...new Set(filteredLaps.map(d => d.car))];
const selectedCars = view(Inputs.select(carOptions, {
  label: "Select cars",
  multiple: true,
  value: carOptions.slice(0, 5)
}));
```

```js
const carLaps = filteredLaps.filter(d => selectedCars.includes(d.car));
if (carLaps.length > 0) {
  display(lapTimeLine(carLaps, {
    width: width,
    height: 400,
    cars: selectedCars
  }));
}
```

## Lap Time Scatter

All laps colored by car.

```js
if (filteredLaps.length > 0) {
  display(lapTimeScatter(filteredLaps, {
    width: width,
    height: 400,
    colorBy: "car",
    showOutliers: false
  }));
}
```

## Pit Stops

```js
if (filteredLaps.some(d => d.pit_time > 0)) {
  display(pitStopTimeline(filteredLaps, {width: width, height: 300}));
} else {
  display(html`<p>No pit stop data available.</p>`);
}
```

## Results Summary

```js
// Calculate final positions by total laps completed and time
const carStats = d3.rollups(
  filteredLaps,
  v => ({
    car: v[0].car,
    driver: v[0].driver,
    class: v[0].class,
    team: v[0].team_name,
    laps: d3.max(v, d => d.lap),
    bestLap: d3.min(v.filter(d => d.lap_time > 30), d => d.lap_time),
    avgLap: d3.mean(v.filter(d => d.lap_time > 30 && d.lap_time < d3.quantile(v.map(x => x.lap_time).filter(t => t > 30).sort(d3.ascending), 0.9)), d => d.lap_time)
  }),
  d => d.car
).map(([_, stats]) => stats)
 .sort((a, b) => b.laps - a.laps || a.avgLap - b.avgLap);

display(Inputs.table(carStats, {
  columns: ["car", "driver", "class", "team", "laps", "bestLap", "avgLap"],
  header: {
    car: "Car",
    driver: "Driver",
    class: "Class",
    team: "Team",
    laps: "Laps",
    bestLap: "Best Lap",
    avgLap: "Avg Lap"
  },
  format: {
    driver: d => htl.html`<a href="../drivers/[driver]?driver=${encodeURIComponent(d)}">${d}</a>`,
    bestLap: d => formatLapTime(d),
    avgLap: d => formatLapTime(d)
  }
}));
```

---

[Back to Events](/events/)
