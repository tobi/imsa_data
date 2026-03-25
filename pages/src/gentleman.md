---
title: Gentleman Driver Report
toc: false
---

```js
import {formatLapTime} from "./components/lap-chart.js";
```

```js
const data = await FileAttachment("data/bronze-lmp2.csv").csv({typed: true});
const tireGapData = await FileAttachment("data/bronze-tire-gap.csv").csv({typed: true});
const eloData = await FileAttachment("data/gentleman-elo.csv").csv({typed: true});
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
      license: sorted[sorted.length - 1].license,
      peak_license: sorted[0].peak_license,
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
const licenseColors = {Platinum: "#e63946", Gold: "#d4a017", Silver: "#8a8d91", Bronze: "#cd7f32"};
const ordinal = n => {
  const s = ["th","st","nd","rd"], v = n % 100;
  return n + (s[(v-20)%10] || s[v] || s[0]);
};

```

# Gentleman Driver Report — LMP2

```js
const selectedDriver = view(Inputs.select(
  driverSummaries.map(d => d.name),
  {label: "Driver", value: driverSummaries.find(d => d.name === "Tobi Lutke")?.name || driverSummaries[0]?.name}
));
```

```js
const driver = driverSummaries.find(d => d.name === selectedDriver);
const driverData = data.filter(d => d.driver_name === selectedDriver);
const allOtherData = data.filter(d => d.driver_name !== selectedDriver && d.gap_to_pro_median != null);
const currentYear = String(Math.max(...data.map(d => +d.year)));
const seasonData = allOtherData.filter(d => d.year === currentYear);
const driverWithRef = driverData.filter(d => d.gap_to_pro_median != null);

const firstEvent = driverData[0];
const lastEvent = driverData[driverData.length - 1];
const driverElo = eloData.filter(d => d.driver_name === selectedDriver).sort((a, b) => new Date(a.session_date) - new Date(b.session_date));
const currentElo = driverElo.length ? +driverElo[driverElo.length - 1].elo_after : null;
const peakElo = driverElo.length ? Math.max(...driverElo.map(d => +d.elo_after)) : null;
const bestEvent = driverWithRef.length ? driverWithRef.reduce((a, b) => +a.gap_to_pro_median < +b.gap_to_pro_median ? a : b) : null;
const worstEvent = driverWithRef.length ? driverWithRef.reduce((a, b) => +a.gap_to_pro_median > +b.gap_to_pro_median ? a : b) : null;
const trackCounts = d3.rollup(driverData, v => v.length, d => d.event);
const favoriteTrack = trackCounts.size ? [...trackCounts.entries()].sort((a, b) => b[1] - a[1])[0][0] : "—";
const seriesSet = new Set(driverData.map(d => d.series_code));
```

<div class="card" style="padding: 1.5rem; margin-bottom: 1.5rem;">
<div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem;">
  <h2 style="margin: 0;">${selectedDriver}</h2>
  <span style="background: ${licenseColors[driver?.license] || '#666'}; color: white; padding: 2px 10px; border-radius: 12px; font-size: 0.85rem; font-weight: 600;">${driver?.license || '?'}</span>
  ${driver?.peak_license && driver.peak_license !== driver.license ? htl.html`<span style="color: #888; font-size: 0.85rem;">Peak: ${driver.peak_license}</span>` : ''}
</div>

<div class="grid grid-cols-5" style="gap: 1rem;">
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Career Races</div>
    <div style="font-size: 1.6rem; font-weight: 700;">${driver?.events ?? "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">${driver?.years_active ?? 0} seasons · ${seriesSet.size} ${seriesSet.size === 1 ? 'series' : 'series'}</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Clean Race Laps</div>
    <div style="font-size: 1.6rem; font-weight: 700;">${driver?.total_laps?.toLocaleString() ?? "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">since ${firstEvent?.year ?? "?"}</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Recent Gap to Pro</div>
    <div style="font-size: 1.6rem; font-weight: 700; color: ${+driver?.recent_gap < +driver?.avg_gap ? '#2a9d8f' : '#e63946'};">${f2(driver?.recent_gap) ? `+${f2(driver.recent_gap)}s` : "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">avg last 5 events</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Improvement</div>
    <div style="font-size: 1.6rem; font-weight: 700; color: ${+driver?.gap_improvement > 0 ? '#2a9d8f' : '#e63946'};">${fmt(driver?.gap_improvement) ? `${+driver.gap_improvement > 0 ? "↓" : "↑"}${fmt(Math.abs(driver.gap_improvement))}s` : "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">first 5 → last 5</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Elo Rating</div>
    <div style="font-size: 1.6rem; font-weight: 700;">${currentElo ?? "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">${peakElo ? `peak ${peakElo}` : ""}</div>
  </div>
</div>

<div class="grid grid-cols-4" style="gap: 1rem; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #333;">
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Best Result</div>
    <div style="font-size: 1.1rem; font-weight: 600;">${bestEvent ? `+${f2(bestEvent.gap_to_pro_median)}s` : "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">${bestEvent ? `${bestEvent.event} ${bestEvent.year}` : ""}</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Career Average</div>
    <div style="font-size: 1.1rem; font-weight: 600;">${f2(driver?.avg_gap) ? `+${f2(driver.avg_gap)}s` : "—"}</div>
    <div style="color: #888; font-size: 0.8rem;">${f1(driver?.avg_gap_pct) ? `${f1(driver.avg_gap_pct)}% off pro pace` : ""}</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Most Raced Track</div>
    <div style="font-size: 1.1rem; font-weight: 600;">${favoriteTrack}</div>
    <div style="color: #888; font-size: 0.8rem;">${trackCounts.get(favoriteTrack) ?? 0} events</div>
  </div>
  <div>
    <div style="color: #888; font-size: 0.75rem; text-transform: uppercase;">Series</div>
    <div style="font-size: 1.1rem; font-weight: 600;">${[...seriesSet].map(s => s.toUpperCase()).join(", ")}</div>
    <div style="color: #888; font-size: 0.8rem;">active ${firstEvent?.year}–${lastEvent?.year}</div>
  </div>
</div>
</div>

## Gap to Pro Over Career

${selectedDriver}'s gap to the car's pro pace (Platinum/Gold drivers' mean of top 2 quartiles across the whole event weekend) vs the field.

```js
const gapMetric = view(Inputs.radio(["Gap (seconds)", "Gap/km (normalized)"], {label: "Metric", value: "Gap/km (normalized)"}));
const usePerKm = gapMetric === "Gap/km (normalized)";
const gapField = usePerKm ? "gap_per_km" : "gap_to_pro_median";
```

```js
const driverWithMetric = driverWithRef.filter(d => d[gapField] != null);
const otherWithMetric = allOtherData.filter(d => d[gapField] != null);
const seasonWithMetric = seasonData.filter(d => d[gapField] != null);

const fieldByLaps = Array.from(
  d3.group(otherWithMetric, d => Math.floor(d.cumulative_laps / 50) * 50),
  ([bucket, rows]) => ({cumulative_laps: bucket, gap: d3.median(rows, d => +d[gapField])})
).sort((a, b) => a.cumulative_laps - b.cumulative_laps);

const seasonByLaps = Array.from(
  d3.group(seasonWithMetric, d => Math.floor(d.cumulative_laps / 50) * 50),
  ([bucket, rows]) => ({cumulative_laps: bucket, gap: d3.median(rows, d => +d[gapField])})
).sort((a, b) => a.cumulative_laps - b.cumulative_laps);

const yLabel = usePerKm ? "← Gap to pro (s/km)" : "← Gap to pro (seconds)";
const maxY = usePerKm ? 3 : 8;

display(Plot.plot({
  width: 960, height: 420, marginLeft: 50, marginBottom: 40,
  x: {label: "Cumulative clean race laps →"},
  y: {label: yLabel, grid: true, domain: [
    Math.min(-0.2, d3.min(driverWithMetric, d => +d[gapField]) - 0.2),
    Math.max(maxY, d3.max(driverWithMetric, d => +d[gapField]) + 0.2)
  ]},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    Plot.line(fieldByLaps, {x: "cumulative_laps", y: "gap", stroke: "#555", strokeWidth: 1.5, strokeDasharray: "6 3"}),
    Plot.line(seasonByLaps, {x: "cumulative_laps", y: "gap", stroke: "#888", strokeWidth: 1.5, strokeDasharray: "2 2"}),
    Plot.dot(driverWithMetric, {
      x: "cumulative_laps", y: gapField,
      fill: d => licenseColors[d.license] || "#e63946", r: 6, opacity: 0.8,
      tip: {channels: {Event: "event", Year: "year", Gap: d => `+${f2(d.gap_to_pro_median)}s`, "Gap/km": d => `+${f2(d.gap_per_km)}s/km`, Series: "series_code"}}
    }),
    ...(driverWithMetric.length >= 3 ? [Plot.linearRegressionY(driverWithMetric, {
      x: "cumulative_laps", y: gapField,
      stroke: licenseColors[driver?.license] || "#e63946", strokeWidth: 2
    })] : []),
  ]
}));
```

<div style="color: #888; font-size: 0.8rem; margin-top: -0.5rem;">
Dots colored by license. Solid line = trend. Dark dashed = all gentleman median. Light dashed = ${currentYear} season median.
</div>

## Elo Progression

```js
const allElo = eloData.filter(d => d.driver_name !== selectedDriver);
const eloByLaps = Array.from(
  d3.group(allElo, d => Math.floor(+d.cumulative_laps / 50) * 50),
  ([bucket, rows]) => ({cumulative_laps: bucket, elo: d3.median(rows, d => +d.elo_after)})
).sort((a, b) => a.cumulative_laps - b.cumulative_laps);

display(Plot.plot({
  width: 960, height: 350, marginLeft: 50,
  x: {label: "Cumulative laps →"},
  y: {label: "Elo Rating", grid: true},
  marks: [
    Plot.ruleY([1500], {stroke: "#888", strokeDasharray: "4 2"}),
    Plot.line(eloByLaps, {x: "cumulative_laps", y: "elo", stroke: "#555", strokeWidth: 1.5, strokeDasharray: "6 3"}),
    Plot.dot(driverElo, {
      x: "cumulative_laps", y: "elo_after",
      fill: d => +d.delta >= 0 ? "#2a9d8f" : "#e63946", r: 6,
      tip: {channels: {Event: "event", Year: "year", "Δ": d => `${+d.delta >= 0 ? "+" : ""}${d.delta}`, Elo: "elo_after"}}
    }),
    Plot.line(driverElo, {x: "cumulative_laps", y: "elo_after",
      stroke: licenseColors[driver?.license] || "#e63946", strokeWidth: 2}),
    Plot.text([{x: eloByLaps[eloByLaps.length-1]?.cumulative_laps, y: eloByLaps[eloByLaps.length-1]?.elo, text: "Field median"}],
      {x: "x", y: "y", text: "text", dx: 5, textAnchor: "start", fill: "#888", fontSize: 10}),
  ]
}));
```

<div style="color: #888; font-size: 0.8rem; margin-top: -0.5rem;">
Green dots = Elo gained. Red = lost. 1500 = starting rating. Dashed = gentleman field median.
</div>

## Event History

```js
const eventTable = driverData.map(d => ({
  Event: `${d.event} ${d.year}`,
  Series: d.series_code.toUpperCase(),
  Car: `#${d.car}`,
  Laps: d.clean_laps,
  "Median": f2(d.median_pace) ? formatLapTime(+d.median_pace) : "—",
  "Best": f2(d.best_lap) ? formatLapTime(+d.best_lap) : "—",
  "Pro Ref": f2(d.pro_median) ? formatLapTime(+d.pro_median) : "—",
  "Gap": f2(d.gap_to_pro_median) ? `+${f2(d.gap_to_pro_median)}s` : "—",
  "Gap/km": f2(d.gap_per_km) ? `+${f2(d.gap_per_km)}s` : "—",
  "Gap %": f1(d.gap_pct) ? `${f1(d.gap_pct)}%` : "—",
}));
display(Inputs.table(eventTable, {
  columns: ["Event", "Series", "Car", "Laps", "Median", "Best", "Pro Ref", "Gap", "Gap/km", "Gap %"]
}));
```

<small>Pro Ref = weighted average of Platinum/Gold drivers' top-quartile laps across all sessions of the event weekend.</small>

## Gap vs Tire Age

How does ${selectedDriver}'s gap change as tires wear? Red line = driver median, compared to all gentleman average.

```js
const driverTireGap = tireGapData.filter(d => d.driver_name === selectedDriver && d.gap != null && d.tire_age <= 30);
const allTireGap = tireGapData.filter(d => d.driver_name !== selectedDriver && d.gap != null && d.tire_age <= 30);
const seasonTireGap = allTireGap.filter(d => d.year == currentYear);
const avgByAge = (rows, minN = 5) => Array.from(
  d3.group(rows, d => d.tire_age),
  ([age, r]) => ({tire_age: age, gap: d3.median(r, d => d.gap), n: r.length})
).filter(d => d.n >= minN).sort((a, b) => a.tire_age - b.tire_age);

display(Plot.plot({
  width: 960, height: 380, marginLeft: 50,
  x: {label: "Tire age (green-flag laps) →", grid: true},
  y: {label: "← Gap to pro (seconds)", grid: true},
  marks: [
    Plot.ruleY([0], {stroke: "#888", strokeDasharray: "4 2"}),
    Plot.line(avgByAge(allTireGap), {x: "tire_age", y: "gap", stroke: "#555", strokeWidth: 1.5, strokeDasharray: "6 3"}),
    Plot.line(avgByAge(seasonTireGap, 3), {x: "tire_age", y: "gap", stroke: "#888", strokeWidth: 1.5, strokeDasharray: "2 2"}),
    Plot.dot(driverTireGap, {
      x: "tire_age", y: "gap", fill: "event", r: 4, opacity: 0.5,
      tip: {channels: {Event: "event", Year: "year", "Driver": d => `${f2(d.bronze_pace)}s`, "Pro": d => `${f2(d.pro_pace)}s`}}
    }),
    Plot.line(avgByAge(driverTireGap, 2), {x: "tire_age", y: "gap", stroke: licenseColors[driver?.license] || "#e63946", strokeWidth: 2.5, curve: "catmull-rom"}),
    Plot.text([{x: 1, y: -0.3, text: "← fresh"}], {x: "x", y: "y", text: "text", fontSize: 10, fill: "#888"}),
    Plot.text([{x: 27, y: -0.3, text: "worn →"}], {x: "x", y: "y", text: "text", fontSize: 10, fill: "#888"}),
  ]
}));
```

## Ranking vs Peers

```js
// Compute avg gap_per_km and current Elo per driver
const driverGapPerKm = new Map();
for (const [id, rows] of d3.group(data, d => d.driver_id)) {
  const valid = rows.filter(d => d.gap_per_km != null);
  if (valid.length >= 2) driverGapPerKm.set(id, d3.mean(valid, d => +d.gap_per_km));
}
const driverEloMap = new Map();
for (const [id, rows] of d3.group(eloData, d => d.driver_id)) {
  const sorted = rows.sort((a, b) => new Date(a.session_date) - new Date(b.session_date));
  driverEloMap.set(id, +sorted[sorted.length - 1].elo_after);
}
for (const d of driverSummaries) {
  d.avg_gap_per_km = driverGapPerKm.get(d.driver_id) ?? null;
  d.elo = driverEloMap.get(d.driver_id) ?? null;
}

// Separate Bronze and Silver rankings with percentiles
const bronzeDrivers = driverSummaries.filter(d => d.license === "Bronze" && d.avg_gap_per_km != null && d.events >= 3);
const silverDrivers = driverSummaries.filter(d => d.license === "Silver" && d.avg_gap_per_km != null && d.events >= 3);

function withPercentile(drivers) {
  const sorted = [...drivers].sort((a, b) => a.avg_gap_per_km - b.avg_gap_per_km);
  return sorted.map((d, i) => ({
    ...d,
    rank: i + 1,
    total: sorted.length,
    percentile: Math.round((1 - i / (sorted.length - 1 || 1)) * 100),
    highlight: d.name === selectedDriver
  }));
}

const bronzeRanked = withPercentile(bronzeDrivers);
const silverRanked = withPercentile(silverDrivers);
const driverLicense = driver?.license;
const relevantRanking = driverLicense === "Silver" ? silverRanked : bronzeRanked;
const otherRanking = driverLicense === "Silver" ? bronzeRanked : silverRanked;
const driverEntry = relevantRanking.find(d => d.highlight);
```

```js
if (driverEntry) {
  const eloText = driverEntry.elo ? ` · Elo ${driverEntry.elo}` : '';
  display(htl.html`<div style="margin-bottom: 0.5rem; color: #ccc; font-size: 1.1rem;">
    <strong>${selectedDriver}</strong> ranks 
    <strong style="color: ${licenseColors[driverLicense]}">#${driverEntry.rank} of ${driverEntry.total} ${driverLicense}</strong> drivers
    by pace (${ordinal(driverEntry.percentile)} percentile)${eloText}
  </div>`);
}
```

**${driverLicense || "Bronze"} Drivers**

```js
display(Plot.plot({
  width: 960, height: Math.max(250, relevantRanking.length * 26 + 40),
  marginLeft: 180,
  x: {label: "Avg gap to pro (s/km) →", grid: true},
  y: {label: null},
  marks: [
    Plot.barX(relevantRanking, {
      x: "avg_gap_per_km", y: "name",
      fill: d => d.highlight ? licenseColors[driverLicense] : "#457b9d",
      sort: {y: "x"},
      tip: {channels: {
        Rank: d => `#${d.rank}/${d.total}`,
        Percentile: d => `${ordinal(d.percentile)}`,
        Events: "events",
        Elo: d => d.elo ?? "—",
        "Recent gap": d => `+${f2(d.recent_gap)}s`
      }}
    }),
    Plot.text(relevantRanking, {
      x: "avg_gap_per_km", y: "name",
      text: d => `#${d.rank}  P${d.percentile}`,
      dx: 5, textAnchor: "start", fontSize: 10,
      fontWeight: d => d.highlight ? "bold" : "normal"
    })
  ]
}));
```

${otherRanking.length > 0 ? htl.html`<details><summary><strong>${driverLicense === "Silver" ? "Bronze" : "Silver"} Drivers</strong> (${otherRanking.length})</summary></details>` : ''}

```js
if (otherRanking.length > 0) {
  display(Plot.plot({
    width: 960, height: Math.max(200, otherRanking.length * 26 + 40),
    marginLeft: 180,
    x: {label: "Avg gap to pro (s/km) →", grid: true},
    y: {label: null},
    marks: [
      Plot.barX(otherRanking, {
        x: "avg_gap_per_km", y: "name",
        fill: d => licenseColors[d.license] || "#888",
        sort: {y: "x"},
        tip: {channels: {Rank: d => `#${d.rank}/${d.total}`, Percentile: d => `${ordinal(d.percentile)}`, Events: "events"}}
      }),
      Plot.text(otherRanking, {
        x: "avg_gap_per_km", y: "name",
        text: d => `#${d.rank}  P${d.percentile}`,
        dx: 5, textAnchor: "start", fontSize: 10
      })
    ]
  }));
}
```

## Gap Consistency

```js
const boxData = data
  .filter(d => d.gap_to_pro_median != null && +d.gap_to_pro_median < 10)
  .filter(d => driverSummaries.find(s => s.driver_id === d.driver_id)?.events >= 3)
  .map(d => ({...d, highlight: d.driver_name === selectedDriver}));

const sortedDriverNames = [...new Set(boxData.map(d => d.driver_name))].sort((a, b) =>
  (d3.median(boxData.filter(d => d.driver_name === a), d => +d.gap_to_pro_median) ?? 99) -
  (d3.median(boxData.filter(d => d.driver_name === b), d => +d.gap_to_pro_median) ?? 99)
);

display(Plot.plot({
  width: 960, height: Math.max(300, sortedDriverNames.length * 28 + 60),
  marginLeft: 180,
  x: {label: "Gap to pro (seconds) →", grid: true, domain: [0, 8]},
  marks: [
    Plot.dot(boxData, Plot.dodgeY("middle", {
      x: "gap_to_pro_median", fy: "driver_name",
      r: d => d.highlight ? 5 : 3,
      fill: d => d.highlight ? (licenseColors[d.license] || "#e63946") : "#457b9d",
      opacity: d => d.highlight ? 0.9 : 0.4,
      tip: {channels: {Event: "event", Year: "year", Gap: d => `+${f2(d.gap_to_pro_median)}s`, Series: "series_code"}}
    })),
    Plot.tickX(
      sortedDriverNames.map(name => {
        const drvData = boxData.filter(d => d.driver_name === name);
        return {driver_name: name, median_gap: d3.median(drvData, d => +d.gap_to_pro_median), license: drvData[0]?.license};
      }),
      {x: "median_gap", fy: "driver_name", stroke: d => d.driver_name === selectedDriver ? (licenseColors[d.license] || "#e63946") : "#333", strokeWidth: 2}
    )
  ],
  fy: {label: null, domain: sortedDriverNames}
}));
```

## Methodology

- **Pro reference pace**: Weighted average of Platinum/Gold drivers' top-quartile laps across all sessions of the event weekend. Weights: race 1.0, qualifying 0.7, warmup 0.6, practice 0.5. Ensures a reference exists even if the pro crashed during the race.
- **Clean laps**: bpillar Q1+Q2 — fastest 50% of each driver's race laps, excluding outlaps, pit laps, and outliers.
- **Gap**: Driver median pace minus pro reference pace. Lower = closer to professional speed.
- **Gap %**: Gap as percentage of reference pace. Normalizes across tracks.
- **Tire age**: Estimated green-flag laps on current tire set. Race sessions only. Bucketed in groups of 3.
- **Improvement**: Average gap in first 5 events minus last 5. ↓ = closing the gap.
- Dark dashed = all gentleman drivers median. Light dashed = current season median.
