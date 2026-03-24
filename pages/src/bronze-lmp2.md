---
title: Bronze LMP2 Report
toc: false
---

```js
import {formatLapTime} from "./components/lap-chart.js";
```

```js
const data = await FileAttachment("data/bronze-lmp2.csv").csv({typed: true});
const tireGapData = await FileAttachment("data/bronze-tire-gap.csv").csv({typed: true});
```

```js
// Build per-driver career summaries
const driverSummaries = Array.from(
  d3.group(data, d => d.driver_id),
  ([id, rows]) => {
    const sorted = rows.sort((a, b) => new Date(a.start_date) - new Date(b.start_date));
    const withRef = sorted.filter(d => d.gap_to_pro_median != null);
    const recent = withRef.slice(-5);
    const early = withRef.slice(0, 5);
    return {
      driver_id: id,
      name: sorted[0].driver_name,
      events: sorted.length,
      total_laps: d3.max(sorted, d => d.cumulative_laps),
      first_race: sorted[0].start_date,
      last_race: sorted[sorted.length - 1].start_date,
      years_active: new Set(sorted.map(d => d.year)).size,
      series: [...new Set(sorted.map(d => d.series_code))].join(", "),
      avg_gap: withRef.length ? d3.mean(withRef, d => d.gap_to_pro_median) : null,
      recent_gap: recent.length ? d3.mean(recent, d => d.gap_to_pro_median) : null,
      early_gap: early.length ? d3.mean(early, d => d.gap_to_pro_median) : null,
      best_gap: withRef.length ? d3.min(withRef, d => d.gap_to_pro_median) : null,
      gap_improvement: (early.length && recent.length)
        ? d3.mean(early, d => d.gap_to_pro_median) - d3.mean(recent, d => d.gap_to_pro_median)
        : null,
      avg_gap_pct: withRef.length ? d3.mean(withRef, d => d.gap_pct) : null,
      rows: sorted
    };
  }
).sort((a, b) => (a.recent_gap ?? 99) - (b.recent_gap ?? 99));

const fmt = (v, decimals = 2) => v != null && isFinite(+v) ? (+v).toFixed(decimals) : null;
const f2 = v => fmt(v, 2);
const f1 = v => fmt(v, 1);
```

# Bronze Driver Report — LMP2

```js
const selectedDriver = view(Inputs.select(
  driverSummaries.filter(d => d.events >= 3).map(d => d.name),
  {label: "Driver", value: driverSummaries.find(d => d.name === "Tobi Lutke")?.name || driverSummaries[0]?.name}
));
```

```js
const driver = driverSummaries.find(d => d.name === selectedDriver);
const driverData = data.filter(d => d.driver_name === selectedDriver);
const allOtherData = data.filter(d => d.driver_name !== selectedDriver && d.gap_to_pro_median != null);
const currentYear = String(Math.max(...data.map(d => +d.year)));
const seasonData = allOtherData.filter(d => d.year === currentYear);
```

<div class="grid grid-cols-4">
  <div class="card">
    <h2>Race Events</h2>
    <span class="big">${driver?.events ?? "—"}</span>
  </div>
  <div class="card">
    <h2>Clean Laps</h2>
    <span class="big">${driver?.total_laps?.toLocaleString() ?? "—"}</span>
  </div>
  <div class="card">
    <h2>Recent Gap to Car</h2>
    <span class="big">${fmt(driver?.recent_gap) ? `+${fmt(driver.recent_gap)}s` : "—"}</span>
  </div>
  <div class="card">
    <h2>Improvement</h2>
    <span class="big">${fmt(driver?.gap_improvement) ? `${+driver.gap_improvement > 0 ? "↓" : "↑"}${fmt(Math.abs(driver.gap_improvement))}s` : "—"}</span>
    <small>first 5 → last 5 events</small>
  </div>
</div>

## Gap to Car Pace Over Career

${selectedDriver}'s gap to their car's reference pace (pro drivers' weighted Q1 laps across the whole event weekend) compared to the field average and this season's average.

```js
const driverWithRef = driverData.filter(d => d.gap_to_pro_median != null);

// Compute rolling averages for the field
const fieldByLaps = Array.from(
  d3.group(allOtherData, d => Math.floor(d.cumulative_laps / 50) * 50),
  ([bucket, rows]) => ({cumulative_laps: bucket, gap: d3.median(rows, d => d.gap_to_pro_median), group: "All Bronze median"})
).sort((a, b) => a.cumulative_laps - b.cumulative_laps);

const seasonByLaps = Array.from(
  d3.group(seasonData, d => Math.floor(d.cumulative_laps / 50) * 50),
  ([bucket, rows]) => ({cumulative_laps: bucket, gap: d3.median(rows, d => d.gap_to_pro_median), group: `${currentYear} Bronze median`})
).sort((a, b) => a.cumulative_laps - b.cumulative_laps);

display(Plot.plot({
  width: 960,
  height: 450,
  marginLeft: 50,
  marginBottom: 40,
  x: {label: "Cumulative clean race laps →"},
  y: {label: "← Gap to car pace (seconds)", grid: true, domain: [
    Math.min(-0.5, d3.min(driverWithRef, d => d.gap_to_pro_median) - 0.5),
    Math.max(8, d3.max(driverWithRef, d => d.gap_to_pro_median) + 0.5)
  ]},
  color: {legend: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    // Field median band
    Plot.line(fieldByLaps, {x: "cumulative_laps", y: "gap", stroke: "#ccc", strokeWidth: 2, strokeDasharray: "6 3"}),
    // Season median band
    Plot.line(seasonByLaps, {x: "cumulative_laps", y: "gap", stroke: "#aaa", strokeWidth: 2, strokeDasharray: "2 2"}),
    // Driver dots
    Plot.dot(driverWithRef, {
      x: "cumulative_laps", y: "gap_to_pro_median",
      fill: "#e63946", r: 6, opacity: 0.8,
      tip: {channels: {Event: "event", Year: "year", Gap: d => `+${f2(d.gap_to_pro_median)}s`, "Gap %": d => `${f1(d.gap_pct)}%`}}
    }),
    // Driver trend line
    ...(driverWithRef.length >= 3 ? [Plot.linearRegressionY(driverWithRef, {
      x: "cumulative_laps", y: "gap_to_pro_median",
      stroke: "#e63946", strokeWidth: 2
    })] : []),
    // Legend annotations
    Plot.text([{x: d3.max(fieldByLaps, d => d.cumulative_laps), y: fieldByLaps[fieldByLaps.length - 1]?.gap, text: "All Bronze"}], {x: "x", y: "y", text: "text", dx: 5, textAnchor: "start", fill: "#999", fontSize: 10}),
  ]
}));
```

## Event History

```js
const eventTable = driverData.map(d => ({
  Event: `${d.event} ${d.year}`,
  Series: d.series_code,
  Car: `#${d.car}`,
  Laps: d.clean_laps,
  "Median": fmt(d.median_pace) ? formatLapTime(d.median_pace) : "—",
  "Best": fmt(d.best_lap) ? formatLapTime(d.best_lap) : "—",
  "Car Ref": fmt(d.pro_median) ? formatLapTime(d.pro_median) : "—",
  "Gap": fmt(d.gap_to_pro_median) ? `+${fmt(d.gap_to_pro_median)}s` : "—",
  "Gap %": fmt(d.gap_pct, 1) ? `${fmt(d.gap_pct, 1)}%` : "—",
}));
```

${Inputs.table(eventTable, {
  columns: ["Event", "Series", "Car", "Laps", "Median", "Best", "Car Ref", "Gap", "Gap %"]
})}

<small>Car Ref = weighted average of pro drivers' top-quartile laps across all sessions of the event weekend (practice + qualifying + race).</small>

## Gap vs Tire Age

How does ${selectedDriver}'s gap change as tires wear? Compared to the average Bronze driver and the ${currentYear} season average at each tire age.

```js
const driverTireGap = tireGapData
  .filter(d => d.driver_name === selectedDriver && d.gap != null && d.tire_age <= 30);

const allTireGap = tireGapData
  .filter(d => d.driver_name !== selectedDriver && d.gap != null && d.tire_age <= 30);

const seasonTireGap = allTireGap.filter(d => d.year == currentYear);

// Average by tire_age for comparison lines
const avgByAge = (rows, minN = 5) => Array.from(
  d3.group(rows, d => d.tire_age),
  ([age, r]) => ({tire_age: age, gap: d3.median(r, d => d.gap), n: r.length})
).filter(d => d.n >= minN).sort((a, b) => a.tire_age - b.tire_age);

const driverAvgByAge = avgByAge(driverTireGap, 2);
const fieldAvgByAge = avgByAge(allTireGap);
const seasonAvgByAge = avgByAge(seasonTireGap, 3);

display(Plot.plot({
  width: 960,
  height: 400,
  marginLeft: 50,
  marginBottom: 40,
  x: {label: "Tire age (green-flag laps) →", grid: true},
  y: {label: "← Gap to car pace (seconds)", grid: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    // Field average
    Plot.line(fieldAvgByAge, {x: "tire_age", y: "gap", stroke: "#ccc", strokeWidth: 2, strokeDasharray: "6 3"}),
    // Season average
    Plot.line(seasonAvgByAge, {x: "tire_age", y: "gap", stroke: "#aaa", strokeWidth: 2, strokeDasharray: "2 2"}),
    // Driver session dots
    Plot.dot(driverTireGap, {
      x: "tire_age", y: "gap",
      fill: "event", r: 4, opacity: 0.5,
      tip: {channels: {Event: "event", Year: "year", "Bronze": d => `${f2(d.bronze_pace)}s`, "Pro ref": d => `${f2(d.pro_pace)}s`}}
    }),
    // Driver median line
    Plot.line(driverAvgByAge, {x: "tire_age", y: "gap", stroke: "#e63946", strokeWidth: 2.5, curve: "catmull-rom"}),
    // Annotations
    Plot.text([{x: 1, y: -0.3, text: "← fresh"}], {x: "x", y: "y", text: "text", fontSize: 10, fill: "#888"}),
    Plot.text([{x: 27, y: -0.3, text: "worn →"}], {x: "x", y: "y", text: "text", fontSize: 10, fill: "#888"}),
  ]
}));
```

<div class="small" style="color: #888; margin-top: -0.5rem;">
Red line = ${selectedDriver}'s median gap. Dots = individual sessions colored by event. Gray dashed = all Bronze drivers median. Dark dashed = ${currentYear} season median. Rising red line = loses more time on worn tires vs pros.
</div>

## Ranking vs Peers

```js
const h2hDrivers = driverSummaries
  .filter(d => d.avg_gap_pct != null && d.events >= 3)
  .map(d => ({
    name: d.name,
    avg_gap_pct: d.avg_gap_pct,
    recent_gap: d.recent_gap,
    events: d.events,
    highlight: d.name === selectedDriver
  }))
  .sort((a, b) => a.avg_gap_pct - b.avg_gap_pct);

display(Plot.plot({
  width: 960,
  height: Math.max(300, h2hDrivers.length * 28 + 60),
  marginLeft: 170,
  x: {label: "Average % slower than car reference →", grid: true, domain: [0, Math.min(8, d3.max(h2hDrivers, d => d.avg_gap_pct) * 1.1)]},
  y: {label: null},
  marks: [
    Plot.barX(h2hDrivers, {
      x: "avg_gap_pct", y: "name",
      fill: d => d.highlight ? "#e63946" : "#457b9d",
      sort: {y: "x"},
      tip: {format: {x: d => `${f2(d)}%`}, channels: {Events: "events", "Recent gap": d => `+${f2(d.recent_gap)}s`}}
    }),
    Plot.text(h2hDrivers, {
      x: "avg_gap_pct", y: "name",
      text: d => `${f1(d.avg_gap_pct)}%`,
      dx: 5, textAnchor: "start", fontSize: 11,
      fontWeight: d => d.highlight ? "bold" : "normal"
    })
  ]
}));
```

## Gap Consistency

```js
const boxData = data
  .filter(d => d.gap_to_pro_median != null && d.gap_to_pro_median < 10)
  .filter(d => driverSummaries.find(s => s.driver_id === d.driver_id)?.events >= 3)
  .map(d => ({...d, highlight: d.driver_name === selectedDriver}));

// Sort by median gap, selected driver highlighted
const sortedDriverNames = [...new Set(boxData.map(d => d.driver_name))].sort((a, b) => {
  const aMedian = d3.median(boxData.filter(d => d.driver_name === a), d => d.gap_to_pro_median);
  const bMedian = d3.median(boxData.filter(d => d.driver_name === b), d => d.gap_to_pro_median);
  return (aMedian ?? 99) - (bMedian ?? 99);
});

display(Plot.plot({
  width: 960,
  height: Math.max(300, sortedDriverNames.length * 30 + 60),
  marginLeft: 170,
  x: {label: "Gap to car reference (seconds) →", grid: true, domain: [0, 8]},
  marks: [
    Plot.dot(boxData, Plot.dodgeY("middle", {
      x: "gap_to_pro_median",
      fy: "driver_name",
      r: d => d.highlight ? 5 : 3,
      fill: d => d.highlight ? "#e63946" : "#457b9d",
      opacity: d => d.highlight ? 0.9 : 0.4,
      tip: {channels: {Event: "event", Year: "year", Gap: d => `+${f2(d.gap_to_pro_median)}s`}}
    })),
    Plot.tickX(
      sortedDriverNames.map(name => ({
        driver_name: name,
        median_gap: d3.median(boxData.filter(d => d.driver_name === name), d => d.gap_to_pro_median)
      })),
      {x: "median_gap", fy: "driver_name", stroke: d => d.driver_name === selectedDriver ? "#e63946" : "#333", strokeWidth: 2}
    )
  ],
  fy: {label: null, domain: sortedDriverNames}
}));
```

## Methodology

- **Car reference pace**: Weighted average of pro drivers' (Platinum/Gold) top-quartile laps across all sessions of the event weekend. Weights: race 1.0, qualifying 0.7, warmup 0.6, practice 0.5. This means every event gets a reference even if the pro crashed during the race.
- **Clean laps**: bpillar Q1+Q2 laps only — the fastest 50% of each driver's laps, excluding outlaps, pit laps, and slow outliers (traffic, off-track moments). This is the standard "representative pace" metric used across endurance racing.
- **Gap**: Bronze median pace minus car reference pace. Lower = closer to professional speed.
- **Gap %**: Gap as percentage of reference pace. Normalizes across different tracks and lap lengths.
- **Tire age**: Estimated green-flag laps on current tire set (`est_tire_age`). Race sessions only. Bucketed in groups of 3 for smoothing.
- **Improvement**: Difference between average gap in first 5 events vs last 5 events. ↓ = getting closer.
- Gray dashed line = median of all Bronze drivers. Dark dashed = current season Bronze median.
