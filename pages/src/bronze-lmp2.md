---
title: Bronze LMP2 Report
toc: false
---

# Bronze Driver Report — LMP2

Career analysis of every Bronze-rated driver currently competing in LMP2 across IMSA, WEC, ELMS, and Asian Le Mans. Tracks their experience, pace development, and gap to professional teammates over time.

```js
import {formatLapTime} from "./components/lap-chart.js";
```

```js
const data = await FileAttachment("data/bronze-lmp2.csv").csv({typed: true});
```

```js
// Build per-driver career summaries
const driverSummaries = Array.from(
  d3.group(data, d => d.driver_id),
  ([id, rows]) => {
    const sorted = rows.sort((a, b) => new Date(a.start_date) - new Date(b.start_date));
    const withPro = sorted.filter(d => d.gap_to_pro_median != null);
    const recent = withPro.slice(-5);
    const early = withPro.slice(0, 5);
    return {
      driver_id: id,
      name: sorted[0].driver_name,
      events: sorted.length,
      total_laps: d3.max(sorted, d => d.cumulative_laps),
      first_race: sorted[0].start_date,
      last_race: sorted[sorted.length - 1].start_date,
      years_active: new Set(sorted.map(d => d.year)).size,
      series: [...new Set(sorted.map(d => d.series_code))].join(", "),
      // Gap stats (median pace vs pro teammate)
      avg_gap: withPro.length ? d3.mean(withPro, d => d.gap_to_pro_median) : null,
      recent_gap: recent.length ? d3.mean(recent, d => d.gap_to_pro_median) : null,
      early_gap: early.length ? d3.mean(early, d => d.gap_to_pro_median) : null,
      best_gap: withPro.length ? d3.min(withPro, d => d.gap_to_pro_median) : null,
      gap_improvement: (early.length && recent.length)
        ? d3.mean(early, d => d.gap_to_pro_median) - d3.mean(recent, d => d.gap_to_pro_median)
        : null,
      avg_gap_pct: withPro.length ? d3.mean(withPro, d => d.gap_pct) : null,
      rows: sorted
    };
  }
).sort((a, b) => (a.recent_gap ?? 99) - (b.recent_gap ?? 99));
```

## Overview

```js
const totalDrivers = driverSummaries.length;
const totalEvents = d3.sum(driverSummaries, d => d.events);
const totalLaps = d3.sum(driverSummaries, d => d.total_laps);
const avgGap = d3.mean(driverSummaries.filter(d => d.avg_gap != null), d => d.avg_gap);
```

<div class="grid grid-cols-4">
  <div class="card">
    <h2>Bronze Drivers</h2>
    <span class="big">${totalDrivers}</span>
  </div>
  <div class="card">
    <h2>Total Race Events</h2>
    <span class="big">${totalEvents}</span>
  </div>
  <div class="card">
    <h2>Total Clean Laps</h2>
    <span class="big">${totalLaps.toLocaleString()}</span>
  </div>
  <div class="card">
    <h2>Avg Gap to Pro</h2>
    <span class="big">${avgGap != null ? `+${avgGap.toFixed(2)}s` : "—"}</span>
  </div>
</div>

## Career Summary

```js
const fmt = (v, decimals = 2) => v != null && isFinite(+v) ? (+v).toFixed(decimals) : null;
const summaryTable = driverSummaries.map(d => ({
  Driver: d.name,
  Events: d.events,
  Laps: d.total_laps,
  "Years": d.years_active,
  Series: d.series,
  "Avg Gap": fmt(d.avg_gap) ? `+${fmt(d.avg_gap)}s` : "—",
  "Recent Gap": fmt(d.recent_gap) ? `+${fmt(d.recent_gap)}s` : "—",
  "Best Gap": fmt(d.best_gap) ? `+${fmt(d.best_gap)}s` : "—",
  "Improvement": fmt(d.gap_improvement) ? `${+d.gap_improvement > 0 ? "↓" : "↑"}${fmt(Math.abs(d.gap_improvement))}s` : "—",
  "Gap %": fmt(d.avg_gap_pct, 1) ? `${fmt(d.avg_gap_pct, 1)}%` : "—"
}));
```

${Inputs.table(summaryTable, {
  sort: "Recent Gap",
  columns: ["Driver", "Events", "Laps", "Years", "Series", "Avg Gap", "Recent Gap", "Best Gap", "Improvement", "Gap %"]
})}

<small>Gap = median lap time difference vs Platinum/Gold teammate in same car, same race. "Recent" = last 5 events. "Improvement" = how much gap shrank from first 5 to last 5 events (↓ = getting closer).</small>

## Gap to Pro Over Career

How each Bronze driver's gap to their professional teammate evolves with experience. The x-axis shows cumulative clean race laps — a proxy for total seat time.

```js
const driverSelect = view(Inputs.select(
  ["All", ...driverSummaries.filter(d => d.events >= 5).map(d => d.name)],
  {label: "Driver", value: "All"}
));
```

```js
const progressionData = data
  .filter(d => d.gap_to_pro_median != null && d.gap_to_pro_median < 10)
  .filter(d => driverSelect === "All" || d.driver_name === driverSelect);
```

```js
display(Plot.plot({
  width: 960,
  height: 500,
  marginLeft: 50,
  marginBottom: 40,
  x: {label: "Cumulative clean race laps →", type: "linear"},
  y: {label: "← Gap to pro (seconds)", reverse: false, domain: [-1, 8], grid: true},
  color: {legend: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    Plot.dot(progressionData, {
      x: "cumulative_laps",
      y: "gap_to_pro_median",
      fill: "driver_name",
      r: 4,
      opacity: 0.7,
      tip: {
        format: {
          x: d => `${d} laps`,
          y: d => `+${d.toFixed(2)}s`
        },
        channels: {
          Event: "event",
          Year: "year",
          Series: "series_code"
        }
      }
    }),
    // Trend line per driver (if enough data)
    ...(driverSelect !== "All" ? [
      Plot.linearRegressionY(progressionData, {
        x: "cumulative_laps",
        y: "gap_to_pro_median",
        stroke: "driver_name",
        strokeWidth: 2,
        strokeDasharray: "6 3"
      })
    ] : [])
  ]
}));
```

## Head-to-Head: Bronze vs Bronze

When two Bronze drivers raced at the same event (not necessarily same car), how do their median paces compare? Normalized by subtracting the class-leading pro pace to account for different tracks and conditions.

```js
// Build head-to-head comparisons
// Normalize each driver's pace by their gap_pct (% slower than pro)
// This makes it comparable across tracks
const h2hData = [];
const eventGroups = d3.group(data.filter(d => d.gap_pct != null), d => `${d.session_id}`);
for (const [key, rows] of eventGroups) {
  if (rows.length >= 2) {
    for (const row of rows) {
      h2hData.push({
        event: `${row.event} ${row.year}`,
        driver: row.driver_name,
        gap_pct: row.gap_pct,
        gap_s: row.gap_to_pro_median
      });
    }
  }
}
```

```js
// Show drivers sorted by their average gap_pct across shared events
const h2hDrivers = Array.from(
  d3.group(h2hData, d => d.driver),
  ([name, rows]) => ({name, avg_gap_pct: d3.mean(rows, d => d.gap_pct), count: rows.length})
).filter(d => d.count >= 3).sort((a, b) => a.avg_gap_pct - b.avg_gap_pct);

display(Plot.plot({
  width: 960,
  height: Math.max(300, h2hDrivers.length * 28 + 60),
  marginLeft: 160,
  x: {label: "Average % slower than pro teammate →", grid: true, domain: [0, Math.min(6, d3.max(h2hDrivers, d => d.avg_gap_pct) * 1.1)]},
  y: {label: null},
  marks: [
    Plot.barX(h2hDrivers, {
      x: "avg_gap_pct",
      y: "name",
      fill: "avg_gap_pct",
      sort: {y: "x"},
      tip: {format: {x: d => `${d.toFixed(2)}%`, y: true}},
      channels: {Events: "count"}
    }),
    Plot.text(h2hDrivers, {
      x: "avg_gap_pct",
      y: "name",
      text: d => `${d.avg_gap_pct.toFixed(1)}%`,
      dx: 5,
      textAnchor: "start",
      fontSize: 11
    })
  ],
  color: {scheme: "YlOrRd", domain: [0, 5], legend: false}
}));
```

## Gap Distribution by Driver

```js
const boxData = data
  .filter(d => d.gap_to_pro_median != null && d.gap_to_pro_median < 10)
  .filter(d => {
    const summary = driverSummaries.find(s => s.driver_id === d.driver_id);
    return summary && summary.events >= 3;
  });

display(Plot.plot({
  width: 960,
  height: Math.max(300, new Set(boxData.map(d => d.driver_name)).size * 32 + 60),
  marginLeft: 160,
  x: {label: "Gap to pro teammate (seconds) →", grid: true, domain: [0, 8]},
  y: {label: null},
  marks: [
    Plot.ruleX([0]),
    Plot.dot(boxData, Plot.dodgeY("middle", {
      x: "gap_to_pro_median",
      fy: "driver_name",
      r: 3,
      fill: "series_code",
      opacity: 0.6,
      tip: {channels: {Event: "event", Year: "year", Gap: d => `+${d.gap_to_pro_median.toFixed(2)}s`}}
    })),
    // Median marker
    Plot.tickX(
      Array.from(d3.group(boxData, d => d.driver_name), ([name, rows]) => ({
        driver_name: name,
        median_gap: d3.median(rows, d => d.gap_to_pro_median)
      })),
      {x: "median_gap", fy: "driver_name", stroke: "red", strokeWidth: 2.5}
    )
  ],
  fy: {label: null, domain: [...new Set(boxData.map(d => d.driver_name))].sort((a, b) => {
    const aMedian = d3.median(boxData.filter(d => d.driver_name === a), d => d.gap_to_pro_median);
    const bMedian = d3.median(boxData.filter(d => d.driver_name === b), d => d.gap_to_pro_median);
    return (aMedian ?? 99) - (bMedian ?? 99);
  })},
  color: {legend: true}
}));
```

## Experience Curve: First 500 Laps

The steepest learning happens in the first few hundred laps. This chart focuses on the early career window.

```js
const earlyData = data
  .filter(d => d.gap_to_pro_median != null && d.cumulative_laps <= 500 && d.gap_to_pro_median < 10);

display(Plot.plot({
  width: 960,
  height: 400,
  marginLeft: 50,
  x: {label: "Cumulative clean laps →", domain: [0, 500]},
  y: {label: "← Gap to pro (seconds)", domain: [-1, 8], grid: true},
  color: {legend: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    Plot.dot(earlyData, {
      x: "cumulative_laps", y: "gap_to_pro_median",
      fill: "driver_name", r: 5, opacity: 0.7,
      tip: {channels: {Event: "event", Year: "year", Laps: "clean_laps"}}
    }),
    Plot.linearRegressionY(earlyData, {
      x: "cumulative_laps", y: "gap_to_pro_median",
      stroke: "#333", strokeWidth: 2, strokeDasharray: "6 3"
    })
  ]
}));
```

## Gap vs Tire Age

How does the gap to the pro teammate change as tires wear? Compares Bronze and Pro median lap times at the same tire age (est_tire_age, bucketed in groups of 3 laps) within the same car and race session. Only bpillar Q1+Q2 laps.

```js
const tireGapData = await FileAttachment("data/bronze-tire-gap.csv").csv({typed: true});
```

```js
const tireDriverSelect = view(Inputs.select(
  ["All (averaged)", ...driverSummaries.filter(d => d.events >= 3).map(d => d.name)],
  {label: "Driver", value: "All (averaged)"}
));
```

```js
const filteredTireGap = tireGapData
  .filter(d => d.gap != null && d.tire_age != null && d.tire_age <= 30)
  .filter(d => tireDriverSelect === "All (averaged)" || d.driver_name === tireDriverSelect);

// For "All" mode, average across all drivers at each tire_age
const tireGapPlotData = tireDriverSelect === "All (averaged)"
  ? Array.from(
      d3.group(filteredTireGap, d => d.tire_age),
      ([age, rows]) => ({
        tire_age: age,
        gap: d3.mean(rows, d => d.gap),
        gap_pct: d3.mean(rows, d => d.gap_pct),
        n: rows.length,
        driver_name: "All Bronze avg"
      })
    ).filter(d => d.n >= 5)
  : filteredTireGap;
```

```js
display(Plot.plot({
  width: 960,
  height: 400,
  marginLeft: 50,
  marginBottom: 40,
  x: {label: "Tire age (green-flag laps) →", grid: true},
  y: {label: "← Gap to pro (seconds)", grid: true},
  color: tireDriverSelect === "All (averaged)" ? undefined : {legend: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    // Individual session dots (faded)
    ...(tireDriverSelect !== "All (averaged)" ? [
      Plot.dot(filteredTireGap, {
        x: "tire_age", y: "gap",
        fill: "event", r: 3, opacity: 0.4,
        tip: {channels: {Event: "event", Year: "year", "Bronze": d => `${d.bronze_pace.toFixed(2)}s`, "Pro": d => `${d.pro_pace.toFixed(2)}s`}}
      })
    ] : []),
    // Average line
    Plot.line(
      tireDriverSelect === "All (averaged)"
        ? tireGapPlotData.sort((a, b) => a.tire_age - b.tire_age)
        : Array.from(
            d3.group(filteredTireGap, d => d.tire_age),
            ([age, rows]) => ({tire_age: age, gap: d3.median(rows, d => d.gap), n: rows.length})
          ).filter(d => d.n >= 2).sort((a, b) => a.tire_age - b.tire_age),
      {x: "tire_age", y: "gap", stroke: "#e63946", strokeWidth: 2.5, curve: "catmull-rom"}
    ),
    // Annotations
    Plot.text([{x: 2, y: -0.3, text: "← fresh tires"}], {x: "x", y: "y", text: "text", fontSize: 11, fill: "#888"}),
    Plot.text([{x: 25, y: -0.3, text: "worn tires →"}], {x: "x", y: "y", text: "text", fontSize: 11, fill: "#888"})
  ]
}));
```

<small>Each dot is one tire-age bucket from one race session. The red line shows the median gap across all sessions. Rising line = Bronze driver loses more time as tires degrade; flat line = consistent tire management.</small>

## Methodology

- **Clean laps**: bpillar Q1+Q2 laps only — the fastest 50% of each driver's laps, excluding outlaps, pit laps, and slow outliers (traffic, off-track moments). This is the standard "representative pace" metric used across endurance racing.
- **Pro teammate**: Platinum or Gold-licensed driver in the same car during the same race session. Their median pace is the reference.
- **Gap**: Bronze median pace minus pro median pace. Lower = closer to professional speed.
- **Gap %**: Gap as percentage of pro pace. Normalizes across different tracks and lap lengths.
- **Improvement**: Difference between average gap in first 5 events vs last 5 events. ↓ means the driver is getting closer to pro pace.
- All lap times are in seconds; shorter = faster.
