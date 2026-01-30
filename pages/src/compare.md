---
title: Compare Drivers
---

# Head-to-Head Comparison

Compare two drivers side by side to see their performance when sharing a car or racing in the same events.

```js
import {eloChart} from "./components/elo-chart.js";
import {formatLapTime} from "./components/lap-chart.js";
```

```js
const drivers = FileAttachment("./data/drivers.csv").csv({typed: true});
const eloHistory = FileAttachment("./data/elo-history.csv").csv({typed: true});
const teammates = FileAttachment("./data/teammates.csv").csv({typed: true});
const eventStats = FileAttachment("./data/event-driver-stats.csv").csv({typed: true});
```

```js
// Create sorted list of driver names for selection
const driverNames = drivers
  .map(d => d.canonical_name)
  .filter(d => d)
  .sort();
```

```js
const driver1Input = Inputs.select(driverNames, {label: "Driver 1", value: driverNames[0]});
const driver1 = Generators.input(driver1Input);
```

```js
const driver2Input = Inputs.select(driverNames, {label: "Driver 2", value: driverNames[Math.min(1, driverNames.length - 1)]});
const driver2 = Generators.input(driver2Input);
```

<div class="grid grid-cols-2" style="max-width: 800px;">
  <div>${driver1Input}</div>
  <div>${driver2Input}</div>
</div>

---

```js
// Get driver info
const driver1Info = drivers.find(d => d.canonical_name === driver1);
const driver2Info = drivers.find(d => d.canonical_name === driver2);
```

## Driver Overview

<div class="grid grid-cols-2">
  <div class="card">
    <h3>${driver1}</h3>
    <p><strong>License:</strong> ${driver1Info?.license || "Unknown"}</p>
    <p><strong>Country:</strong> ${driver1Info?.country || "-"}</p>
    <p><strong>Team:</strong> ${driver1Info?.team || "-"}</p>
    <p><strong>Class:</strong> ${driver1Info?.last_class || "-"}</p>
  </div>
  <div class="card">
    <h3>${driver2}</h3>
    <p><strong>License:</strong> ${driver2Info?.license || "Unknown"}</p>
    <p><strong>Country:</strong> ${driver2Info?.country || "-"}</p>
    <p><strong>Team:</strong> ${driver2Info?.team || "-"}</p>
    <p><strong>Class:</strong> ${driver2Info?.last_class || "-"}</p>
  </div>
</div>

## Elo Rating Comparison

```js
const elo1 = eloHistory.filter(d => d.driver?.toLowerCase() === driver1?.toLowerCase());
const elo2 = eloHistory.filter(d => d.driver?.toLowerCase() === driver2?.toLowerCase());
const combinedElo = [...elo1, ...elo2];
```

```js
if (combinedElo.length > 0) {
  display(eloChart(combinedElo, {
    width: 900,
    height: 400,
    drivers: [driver1, driver2],
    colorBy: "driver"
  }));
} else {
  display(htl.html`<div class="note">No Elo history available for these drivers.</div>`);
}
```

## Shared Events (Teammates)

When these drivers shared a car in the same event:

```js
// Find events where both drivers were teammates (shared a car)
const sharedEvents = teammates.filter(d =>
  (d.driver_a?.toLowerCase() === driver1?.toLowerCase() && d.driver_b?.toLowerCase() === driver2?.toLowerCase()) ||
  (d.driver_a?.toLowerCase() === driver2?.toLowerCase() && d.driver_b?.toLowerCase() === driver1?.toLowerCase())
).sort((a, b) => new Date(b.event_date) - new Date(a.event_date));
```

```js
if (sharedEvents.length > 0) {
  // Calculate head-to-head record
  let driver1Wins = 0;
  let driver2Wins = 0;

  const sharedWithWinner = sharedEvents.map(e => {
    const isDriver1A = e.driver_a?.toLowerCase() === driver1?.toLowerCase();
    const d1Best = isDriver1A ? e.best_lap_a : e.best_lap_b;
    const d2Best = isDriver1A ? e.best_lap_b : e.best_lap_a;

    let winner = "-";
    if (d1Best && d2Best && d1Best > 0 && d2Best > 0) {
      if (d1Best < d2Best) {
        winner = driver1;
        driver1Wins++;
      } else {
        winner = driver2;
        driver2Wins++;
      }
    }

    return {
      year: e.year,
      event: e.event,
      class: e.class,
      car: e.car,
      team: e.team,
      best1: isDriver1A ? e.best_lap_a : e.best_lap_b,
      best2: isDriver1A ? e.best_lap_b : e.best_lap_a,
      winner: winner,
      gap: d1Best && d2Best ? Math.abs(d1Best - d2Best).toFixed(3) : "-"
    };
  });

  display(htl.html`<div class="tip">
    <strong>Head-to-Head Record:</strong> ${driver1}: ${driver1Wins} wins | ${driver2}: ${driver2Wins} wins | ${sharedEvents.length - driver1Wins - driver2Wins} ties
  </div>`);

  display(Inputs.table(sharedWithWinner, {
    columns: ["year", "event", "class", "car", "team", "best1", "best2", "winner", "gap"],
    header: {
      year: "Year",
      event: "Event",
      class: "Class",
      car: "Car #",
      team: "Team",
      best1: `${driver1} Best`,
      best2: `${driver2} Best`,
      winner: "Faster",
      gap: "Gap (s)"
    },
    format: {
      best1: d => d ? formatLapTime(d) : "-",
      best2: d => d ? formatLapTime(d) : "-",
      winner: d => {
        if (d === "-") return d;
        const color = d === driver1 ? "#2a9d8f" : "#e63946";
        return htl.html`<span style="color: ${color}; font-weight: bold;">${d}</span>`;
      }
    },
    width: {
      year: 60,
      event: 120,
      class: 70,
      car: 50,
      team: 150,
      best1: 90,
      best2: 90,
      winner: 120,
      gap: 70
    }
  }));
} else {
  display(htl.html`<div class="note">These drivers have never shared a car in the database.</div>`);
}
```

## Gap Trend

```js
if (sharedEvents.length >= 2) {
  const gapData = sharedEvents
    .map(e => {
      const isDriver1A = e.driver_a?.toLowerCase() === driver1?.toLowerCase();
      const d1Best = isDriver1A ? e.best_lap_a : e.best_lap_b;
      const d2Best = isDriver1A ? e.best_lap_b : e.best_lap_a;
      if (!d1Best || !d2Best || d1Best <= 0 || d2Best <= 0) return null;
      return {
        date: new Date(e.event_date),
        event: e.event,
        gap: d1Best - d2Best  // Positive = driver1 slower, negative = driver1 faster
      };
    })
    .filter(d => d !== null)
    .sort((a, b) => a.date - b.date);

  if (gapData.length >= 2) {
    display(Plot.plot({
      width: 900,
      height: 300,
      marginLeft: 60,
      x: {type: "time", label: "Date"},
      y: {
        label: `Gap (s) - Negative = ${driver1} faster`,
        domain: [Math.min(-1, ...gapData.map(d => d.gap)) - 0.2, Math.max(1, ...gapData.map(d => d.gap)) + 0.2]
      },
      marks: [
        Plot.ruleY([0], {stroke: "#ccc"}),
        Plot.line(gapData, {x: "date", y: "gap", stroke: "#457b9d", strokeWidth: 2}),
        Plot.dot(gapData, {
          x: "date",
          y: "gap",
          fill: d => d.gap < 0 ? "#2a9d8f" : "#e63946",
          r: 5,
          tip: true,
          title: d => `${d.event}: ${d.gap > 0 ? '+' : ''}${d.gap.toFixed(3)}s`
        })
      ]
    }));
  }
}
```

## Same Event Performance

Events where both drivers competed but not as teammates:

```js
// Get event stats for both drivers
const events1 = eventStats.filter(d => d.driver?.toLowerCase() === driver1?.toLowerCase());
const events2 = eventStats.filter(d => d.driver?.toLowerCase() === driver2?.toLowerCase());

// Find events where both competed
const eventSet1 = new Set(events1.map(e => `${e.series_code}-${e.year}-${e.event}`));
const eventSet2 = new Set(events2.map(e => `${e.series_code}-${e.year}-${e.event}`));
const commonEventKeys = [...eventSet1].filter(k => eventSet2.has(k));

const sameEventData = commonEventKeys.map(key => {
  const e1 = events1.find(e => `${e.series_code}-${e.year}-${e.event}` === key);
  const e2 = events2.find(e => `${e.series_code}-${e.year}-${e.event}` === key);
  // Skip if they were teammates
  if (e1.car === e2.car) return null;
  return {
    year: e1.year,
    event: e1.event,
    class1: e1.class,
    class2: e2.class,
    car1: e1.car,
    car2: e2.car,
    best1: e1.best_lap,
    best2: e2.best_lap,
    laps1: e1.laps,
    laps2: e2.laps
  };
}).filter(d => d !== null).sort((a, b) => b.year - a.year || a.event.localeCompare(b.event));
```

```js
if (sameEventData.length > 0) {
  display(Inputs.table(sameEventData.slice(0, 20), {
    columns: ["year", "event", "class1", "car1", "best1", "class2", "car2", "best2"],
    header: {
      year: "Year",
      event: "Event",
      class1: `${driver1} Class`,
      car1: `${driver1} Car`,
      best1: `${driver1} Best`,
      class2: `${driver2} Class`,
      car2: `${driver2} Car`,
      best2: `${driver2} Best`
    },
    format: {
      best1: d => d ? formatLapTime(d) : "-",
      best2: d => d ? formatLapTime(d) : "-"
    }
  }));
} else {
  display(htl.html`<div class="note">No events found where both drivers competed in different cars.</div>`);
}
