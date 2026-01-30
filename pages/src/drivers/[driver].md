---
title: Driver Detail
---

```js
import {eloChart, eloSparkline} from "../components/elo-chart.js";
import {statCard, statCardGrid, licenseBadge} from "../components/stat-card.js";
import {formatLapTime} from "../components/lap-chart.js";
```

```js
// Get driver name from URL parameter
const params = new URLSearchParams(window.location.search);
const driverParam = params.get("driver") || "";
const driverName = decodeURIComponent(driverParam);
```

```js
const drivers = FileAttachment("../data/drivers.csv").csv({typed: true});
const eloHistory = FileAttachment("../data/elo-history.csv").csv({typed: true});
const teammates = FileAttachment("../data/teammates.csv").csv({typed: true});
const eventStats = FileAttachment("../data/event-driver-stats.csv").csv({typed: true});
const raceLaps = FileAttachment("../data/race-laps.csv").csv({typed: true});
const licenseHistory = FileAttachment("../data/driver-license-history.csv").csv({typed: true});
const trackStats = FileAttachment("../data/driver-track-stats.csv").csv({typed: true});
const bestResults = FileAttachment("../data/driver-best-results.csv").csv({typed: true});
const events = FileAttachment("../data/events.csv").csv({typed: true});
```

```js
// Find the driver record
const driver = drivers.find(d =>
  d.canonical_name?.toLowerCase() === driverName.toLowerCase() ||
  d.driver_id?.toLowerCase() === driverName.toLowerCase()
);

const displayName = driver?.canonical_name || driverName || "Unknown Driver";
```

```js
if (!driver) {
  display(htl.html`<div class="warning">Driver not found: ${driverName}</div>`);
}
```

```js
// License colors
const licenseColors = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51"
};

// Calculate quick stats
const currentElo = driverElo.length > 0 ? driverElo[driverElo.length - 1].elo : null;
const peakElo = driverElo.length > 0 ? Math.max(...driverElo.map(d => d.elo)) : null;
const totalLaps = driverElo.length > 0 ? driverElo[driverElo.length - 1].cumulative_laps : 0;
const eloTrend = driverElo.length > 1 ? currentElo - driverElo[Math.max(0, driverElo.length - 6)].elo : 0;
```

```js
display(htl.html`
<div class="driver-hero">
  <div class="driver-hero-main">
    <div class="driver-identity">
      <h1 class="driver-name">${displayName}</h1>
      <div class="driver-badges">
        ${driver?.license ? htl.html`<span class="license-badge" style="background: ${licenseColors[driver.license] || '#666'}">${driver.license}</span>` : ''}
        ${driver?.country ? htl.html`<span class="country-badge">${driver.country}</span>` : ''}
      </div>
      ${driver?.team ? htl.html`<div class="driver-team">${driver.team}</div>` : ''}
    </div>
    <div class="driver-elo-display">
      <div class="elo-current">
        <span class="elo-value">${currentElo || '-'}</span>
        <span class="elo-label">Elo Rating</span>
        ${eloTrend !== 0 ? htl.html`<span class="elo-trend ${eloTrend > 0 ? 'up' : 'down'}">${eloTrend > 0 ? '▲' : '▼'} ${Math.abs(eloTrend)}</span>` : ''}
      </div>
      <div class="elo-peak">
        <span class="peak-value">${peakElo || '-'}</span>
        <span class="peak-label">Peak</span>
      </div>
    </div>
  </div>
  <div class="driver-hero-stats">
    <div class="hero-stat">
      <span class="stat-num">${driverEvents.length}</span>
      <span class="stat-txt">Events</span>
    </div>
    <div class="hero-stat">
      <span class="stat-num">${totalLaps?.toLocaleString() || 0}</span>
      <span class="stat-txt">Laps</span>
    </div>
    <div class="hero-stat">
      <span class="stat-num">${driver?.last_class || '-'}</span>
      <span class="stat-txt">Class</span>
    </div>
    <div class="hero-stat">
      <span class="stat-num">${[...new Set(driverEvents.map(e => e.series_code))].length}</span>
      <span class="stat-txt">Series</span>
    </div>
  </div>
</div>
`);
```

```js
// Get this driver's Elo history
const driverElo = eloHistory.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase()
).sort((a, b) => new Date(a.session_date) - new Date(b.session_date));

// Get this driver's event stats
const driverEvents = eventStats.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase()
).sort((a, b) => new Date(b.event_date) - new Date(a.event_date));

// Get teammate data for this driver
const driverTeammates = teammates.filter(d =>
  d.driver_a?.toLowerCase() === driverName.toLowerCase() ||
  d.driver_b?.toLowerCase() === driverName.toLowerCase()
);

// Get license history for this driver
const driverLicenseHistory = licenseHistory.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase()
).sort((a, b) => new Date(a.first_seen_date) - new Date(b.first_seen_date));

// Get track stats for this driver
const driverTrackStats = trackStats.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase()
).sort((a, b) => b.events - a.events);

// Get best results for this driver
const driverBestResults = bestResults.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase()
).sort((a, b) => new Date(b.start_date) - new Date(a.start_date));
```

```js
// Calculate career stats from results
const totalWins = driverBestResults.filter(r => r.is_win).length;
const totalPodiums = driverBestResults.filter(r => r.is_podium).length;
const totalTop5 = driverBestResults.filter(r => r.is_top5).length;
const totalTop10 = driverBestResults.filter(r => r.is_top10).length;
const totalRaces = driverBestResults.length;
```

## Career Stats

<div class="career-stats-row">
  <div class="career-stat wins">
    <span class="career-stat-value">${totalWins}</span>
    <span class="career-stat-label">Wins</span>
  </div>
  <div class="career-stat podiums">
    <span class="career-stat-value">${totalPodiums}</span>
    <span class="career-stat-label">Podiums</span>
  </div>
  <div class="career-stat">
    <span class="career-stat-value">${totalTop5}</span>
    <span class="career-stat-label">Top 5</span>
  </div>
  <div class="career-stat">
    <span class="career-stat-value">${totalTop10}</span>
    <span class="career-stat-label">Top 10</span>
  </div>
  <div class="career-stat">
    <span class="career-stat-value">${totalRaces}</span>
    <span class="career-stat-label">Races</span>
  </div>
</div>

## Career Timeline

```js
// Build career timeline data combining events with results for position
const timelineData = driverBestResults.map(r => ({
  date: new Date(r.start_date),
  year: r.year,
  event: r.event_name,
  track: r.track,
  series: r.series_code,
  class: r.class,
  position: r.position,
  isWin: r.is_win,
  isPodium: r.is_podium,
  team: r.team,
  car: r.car
})).filter(d => d.position && d.position > 0)
  .sort((a, b) => a.date - b.date);
```

```js
if (timelineData.length > 0) {
  const maxPos = Math.min(20, Math.max(...timelineData.map(d => d.position)));

  display(Plot.plot({
    width: Math.min(width, 900),
    height: 280,
    marginLeft: 50,
    marginBottom: 40,
    marginTop: 20,
    x: {
      type: "time",
      label: "Date"
    },
    y: {
      label: "Finishing Position",
      domain: [maxPos + 1, 0],
      reverse: false,
      grid: true
    },
    color: {
      domain: ["Win", "Podium", "Top 5", "Other"],
      range: ["#ffd700", "#c0c0c0", "#2a9d8f", "#999"]
    },
    marks: [
      Plot.ruleY([1, 3, 5], {stroke: "#ddd", strokeDasharray: "3,3"}),
      Plot.dot(timelineData, {
        x: "date",
        y: "position",
        fill: d => d.isWin ? "Win" : d.isPodium ? "Podium" : d.position <= 5 ? "Top 5" : "Other",
        r: d => d.isWin ? 10 : d.isPodium ? 8 : 6,
        stroke: "#fff",
        strokeWidth: 1,
        tip: true,
        title: d => `${d.event}\n${d.track}\nP${d.position} in ${d.class}\n${d.team} #${d.car}`
      }),
      Plot.text(timelineData.filter(d => d.isWin), {
        x: "date",
        y: "position",
        text: "🏆",
        dy: -15,
        fontSize: 14
      })
    ]
  }));
} else {
  display(htl.html`<div class="note">No career timeline data available.</div>`);
}
```

## Elo Rating History

```js
// Add sparkline summary
if (driverElo.length > 0) {
  const currentElo = driverElo[driverElo.length - 1].elo;
  const startElo = driverElo[0].elo;
  const peakElo = Math.max(...driverElo.map(d => d.elo));
  const lowElo = Math.min(...driverElo.map(d => d.elo));
  const trend = currentElo - startElo;

  display(htl.html`<div class="grid grid-cols-2" style="margin-bottom: 1rem;">
    <div style="display: flex; align-items: center; gap: 1rem;">
      ${eloSparkline(driverElo, {width: 200, height: 50})}
      <span style="color: ${trend >= 0 ? '#2a9d8f' : '#e63946'}; font-weight: bold;">
        ${trend >= 0 ? '+' : ''}${trend} overall
      </span>
    </div>
    <div class="note">
      Range: ${lowElo} - ${peakElo} (${peakElo - lowElo} spread)
    </div>
  </div>`);
}
```

```js
if (driverElo.length > 0) {
  display(eloChart(driverElo, {
    width: 900,
    height: 350,
    showDelta: true,
    colorBy: "class"
  }));
} else {
  display(htl.html`<div class="note">No Elo history available for this driver.</div>`);
}
```

## Best Results

```js
// Get wins and podiums
const wins = driverBestResults.filter(r => r.is_win);
const podiums = driverBestResults.filter(r => r.is_podium && !r.is_win);
```

### Wins

```js
if (wins.length > 0) {
  display(Inputs.table(wins, {
    columns: ["year", "event", "series_code", "class", "team", "car", "track"],
    header: {
      year: "Year",
      event: "Event",
      series_code: "Series",
      class: "Class",
      team: "Team",
      car: "Car #",
      track: "Track"
    },
    width: {
      year: 60,
      event: 150,
      series_code: 60,
      class: 80,
      team: 180,
      car: 50,
      track: 150
    }
  }));
} else {
  display(htl.html`<div class="note">No wins recorded.</div>`);
}
```

### Other Podiums (P2, P3)

```js
if (podiums.length > 0) {
  display(Inputs.table(podiums, {
    columns: ["year", "event", "series_code", "class", "position", "team", "car", "track"],
    header: {
      year: "Year",
      event: "Event",
      series_code: "Series",
      class: "Class",
      position: "Pos",
      team: "Team",
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
      class: 80,
      position: 40,
      team: 150,
      car: 50,
      track: 150
    }
  }));
} else {
  display(htl.html`<div class="note">No other podiums recorded.</div>`);
}
```

## Teammate Comparisons

```js
// Aggregate teammate data - who did they share cars with most often?
const teammateAggregates = new Map();

for (const row of driverTeammates) {
  const isDriverA = row.driver_a?.toLowerCase() === driverName.toLowerCase();
  const teammate = isDriverA ? row.driver_b : row.driver_a;
  const myBest = isDriverA ? row.best_lap_a : row.best_lap_b;
  const theirBest = isDriverA ? row.best_lap_b : row.best_lap_a;
  const myLaps = isDriverA ? row.laps_a : row.laps_b;
  const theirLaps = isDriverA ? row.laps_b : row.laps_a;
  const myQ1Pct = isDriverA ? row.q1_pct_a : row.q1_pct_b;
  const theirQ1Pct = isDriverA ? row.q1_pct_b : row.q1_pct_a;

  if (!teammate) continue;

  if (!teammateAggregates.has(teammate)) {
    teammateAggregates.set(teammate, {
      name: teammate,
      events: 0,
      wins: 0,
      losses: 0,
      totalGap: 0,
      validGaps: 0,
      totalMyLaps: 0,
      totalTheirLaps: 0,
      myQ1PctSum: 0,
      theirQ1PctSum: 0,
      q1PctCount: 0
    });
  }

  const agg = teammateAggregates.get(teammate);
  agg.events++;
  agg.totalMyLaps += myLaps || 0;
  agg.totalTheirLaps += theirLaps || 0;

  if (myQ1Pct && theirQ1Pct) {
    agg.myQ1PctSum += myQ1Pct;
    agg.theirQ1PctSum += theirQ1Pct;
    agg.q1PctCount++;
  }

  if (myBest && theirBest && myBest > 0 && theirBest > 0) {
    agg.validGaps++;
    if (myBest < theirBest) {
      agg.wins++;
      agg.totalGap += theirBest - myBest;
    } else {
      agg.losses++;
      agg.totalGap -= myBest - theirBest;
    }
  }
}

const teammateList = Array.from(teammateAggregates.values())
  .map(t => ({
    ...t,
    avgGap: t.validGaps > 0 ? (t.totalGap / t.validGaps).toFixed(3) : "-",
    record: `${t.wins}-${t.losses}`,
    winPct: t.validGaps > 0 ? ((t.wins / t.validGaps) * 100).toFixed(0) + "%" : "-",
    avgMyQ1Pct: t.q1PctCount > 0 ? (t.myQ1PctSum / t.q1PctCount).toFixed(1) : null,
    avgTheirQ1Pct: t.q1PctCount > 0 ? (t.theirQ1PctSum / t.q1PctCount).toFixed(1) : null
  }))
  .sort((a, b) => b.events - a.events);
```

```js
if (teammateList.length > 0) {
  display(htl.html`<div class="note" style="margin-bottom: 0.5rem;">
    Head-to-head based on best lap times per event. Negative gap = driver is faster.
  </div>`);

  display(Inputs.table(teammateList, {
    columns: ["name", "events", "record", "winPct", "avgGap", "totalMyLaps", "totalTheirLaps"],
    header: {
      name: "Teammate",
      events: "Events",
      record: "H2H Record",
      winPct: "Win %",
      avgGap: "Avg Gap (s)",
      totalMyLaps: "My Laps",
      totalTheirLaps: "Their Laps"
    },
    format: {
      name: d => htl.html`<a href="./[driver]?driver=${encodeURIComponent(d)}">${d}</a>`,
      avgGap: d => {
        if (d === "-") return d;
        const gap = parseFloat(d);
        // Negate: positive internal gap (driver faster) shows as negative (lower time)
        const displayGap = -gap;
        const color = displayGap < 0 ? "#2a9d8f" : "#e63946";
        return htl.html`<span style="color: ${color}">${displayGap > 0 ? "+" : ""}${displayGap.toFixed(3)}</span>`;
      },
      winPct: d => {
        if (d === "-") return d;
        const pct = parseInt(d);
        const color = pct >= 50 ? "#2a9d8f" : "#e63946";
        return htl.html`<span style="color: ${color}">${d}</span>`;
      }
    },
    width: {
      name: 200,
      events: 70,
      record: 90,
      winPct: 70,
      avgGap: 100,
      totalMyLaps: 80,
      totalTheirLaps: 90
    }
  }));
} else {
  display(htl.html`<div class="note">No teammate data available.</div>`);
}
```

## Track-by-Track Performance

Q1% measures the percentage of laps in the top 25% of the driver's own stint - a relative consistency metric that is valid across events.

```js
if (driverTrackStats.length > 0) {
  display(Inputs.table(driverTrackStats, {
    columns: ["track", "track_country", "events", "total_laps", "avg_q1_pct", "first_year", "last_year"],
    header: {
      track: "Track",
      track_country: "Country",
      events: "Events",
      total_laps: "Total Laps",
      avg_q1_pct: "Avg Q1%",
      first_year: "First",
      last_year: "Last"
    },
    format: {
      avg_q1_pct: d => d ? d.toFixed(1) + "%" : "-",
      total_laps: d => d ? d.toLocaleString() : "-"
    },
    width: {
      track: 200,
      track_country: 100,
      events: 60,
      total_laps: 80,
      avg_q1_pct: 80,
      first_year: 60,
      last_year: 60
    }
  }));
} else {
  display(htl.html`<div class="note">No track statistics available.</div>`);
}
```

```js
// Track performance chart
if (driverTrackStats.length > 0 && driverTrackStats.some(t => t.avg_q1_pct)) {
  const sortedTracks = driverTrackStats
    .filter(t => t.avg_q1_pct && t.events >= 2)
    .sort((a, b) => b.avg_q1_pct - a.avg_q1_pct);

  if (sortedTracks.length > 0) {
    display(htl.html`<h4 style="margin-top: 1rem;">Track Consistency (Q1% - higher is better)</h4>`);
    display(Plot.plot({
      width: 800,
      height: Math.max(200, sortedTracks.length * 25),
      marginLeft: 150,
      x: {
        label: "Avg Q1%",
        domain: [0, 100]
      },
      y: {
        label: null
      },
      marks: [
        Plot.barX(sortedTracks, {
          y: d => d.track.slice(0, 25),
          x: "avg_q1_pct",
          fill: d => d.avg_q1_pct >= 50 ? "#2a9d8f" : "#e76f51",
          tip: true,
          title: d => `${d.track}\n${d.events} events, ${d.total_laps} laps\nAvg Q1%: ${d.avg_q1_pct.toFixed(1)}%`
        }),
        Plot.ruleX([50], {stroke: "#999", strokeDasharray: "4,4"})
      ]
    }));
  }
}
```

## License History

```js
if (driverLicenseHistory.length > 0) {
  const licenseColors = {
    Platinum: "#e63946",
    Gold: "#ffd700",
    Silver: "#c0c0c0",
    Bronze: "#cd7f32"
  };

  display(Plot.plot({
    width: 600,
    height: 150,
    marginLeft: 80,
    x: {
      type: "time",
      label: "Date"
    },
    y: {
      label: "License",
      domain: ["Bronze", "Silver", "Gold", "Platinum"]
    },
    marks: [
      Plot.line(driverLicenseHistory.map(d => ({
        ...d,
        date: new Date(d.first_seen_date)
      })), {
        x: "date",
        y: "license",
        stroke: "#457b9d",
        strokeWidth: 2,
        curve: "step-after"
      }),
      Plot.dot(driverLicenseHistory.map(d => ({
        ...d,
        date: new Date(d.first_seen_date)
      })), {
        x: "date",
        y: "license",
        fill: d => licenseColors[d.license] || "#9b5de5",
        r: 8,
        tip: true,
        title: d => `${d.license}\n${d.series_code} ${d.year}`
      })
    ]
  }));

  display(Inputs.table(driverLicenseHistory, {
    columns: ["year", "series_code", "license"],
    header: {
      year: "Year",
      series_code: "Series",
      license: "License"
    },
    format: {
      license: d => htl.html`<span style="color: ${licenseColors[d] || '#9b5de5'}; font-weight: bold;">${d}</span>`
    },
    width: {
      year: 80,
      series_code: 80,
      license: 100
    }
  }));
} else {
  display(htl.html`<div class="note">No license history available.</div>`);
}
```

## Stint Lap Cohort Analysis

Shows how lap times evolve within each stint, normalized as delta from the car's representative pace (avg bpillar Q1+Q2) for each event. This allows comparison across different tracks.

```js
// Get this driver's race laps with event context
const driverLaps = raceLaps.filter(d =>
  d.driver?.toLowerCase() === driverName.toLowerCase() &&
  d.lap_time > 30 && d.lap_time < 300 &&
  d.stint_lap >= 0 && d.stint_lap <= 15
);

// Get car's representative pace (avg_q12) per event from eventStats
const carPaceByEvent = new Map();
for (const e of driverEvents) {
  if (e.avg_q12 && e.avg_q12 > 0) {
    const key = `${e.series_code}-${e.year}-${e.event}-${e.car}`;
    carPaceByEvent.set(key, e.avg_q12);
  }
}

// Calculate delta from car's representative pace for each lap
const lapsWithDelta = driverLaps.map(d => {
  const key = `${d.series_code}-${d.year}-${d.event}-${d.car}`;
  const refPace = carPaceByEvent.get(key);
  return {
    ...d,
    delta: refPace ? d.lap_time - refPace : null
  };
}).filter(d => d.delta !== null && Math.abs(d.delta) < 30); // Filter extreme outliers

// Aggregate by stint_lap
const stintCohort = d3.rollups(
  lapsWithDelta,
  v => ({
    count: v.length,
    avgDelta: d3.mean(v, d => d.delta),
    medianDelta: d3.median(v, d => d.delta),
    minDelta: d3.quantile(v.map(d => d.delta).sort(d3.ascending), 0.1),
    maxDelta: d3.quantile(v.map(d => d.delta).sort(d3.ascending), 0.9)
  }),
  d => d.stint_lap
).map(([stint_lap, stats]) => ({stint_lap, ...stats}))
 .filter(d => d.count >= 5) // Need enough samples
 .sort((a, b) => a.stint_lap - b.stint_lap);
```

```js
if (stintCohort.length > 0) {
  const outlap = stintCohort.find(d => d.stint_lap === 0);
  const flyingLaps = stintCohort.filter(d => d.stint_lap >= 1 && d.stint_lap <= 4);
  const avgFlyingDelta = flyingLaps.length > 0 ? d3.mean(flyingLaps, d => d.avgDelta) : null;

  // Calculate degradation (difference between early and late stint)
  const earlyLaps = stintCohort.filter(d => d.stint_lap >= 1 && d.stint_lap <= 3);
  const lateLaps = stintCohort.filter(d => d.stint_lap >= 8 && d.stint_lap <= 12);
  const earlyAvg = earlyLaps.length > 0 ? d3.mean(earlyLaps, d => d.avgDelta) : null;
  const lateAvg = lateLaps.length > 0 ? d3.mean(lateLaps, d => d.avgDelta) : null;
  const degradation = (earlyAvg !== null && lateAvg !== null) ? lateAvg - earlyAvg : null;

  display(htl.html`<div class="grid grid-cols-4" style="max-width: 800px;">
    <div class="card">
      <h4>Avg Outlap Delta</h4>
      <div class="big">${outlap ? (outlap.avgDelta > 0 ? "+" : "") + outlap.avgDelta.toFixed(2) + "s" : "-"}</div>
      <div class="note">${outlap ? outlap.count + " samples" : ""}</div>
    </div>
    <div class="card">
      <h4>Avg Flying Delta (1-4)</h4>
      <div class="big">${avgFlyingDelta !== null ? (avgFlyingDelta > 0 ? "+" : "") + avgFlyingDelta.toFixed(2) + "s" : "-"}</div>
    </div>
    <div class="card">
      <h4>Outlap Penalty</h4>
      <div class="big">${outlap && avgFlyingDelta !== null ? "+" + (outlap.avgDelta - avgFlyingDelta).toFixed(2) + "s" : "-"}</div>
    </div>
    <div class="card">
      <h4>Stint Degradation</h4>
      <div class="big" style="color: ${degradation !== null && degradation > 0.5 ? '#e63946' : '#2a9d8f'}">
        ${degradation !== null ? (degradation > 0 ? "+" : "") + degradation.toFixed(2) + "s" : "-"}
      </div>
      <div class="note">Early vs Late stint</div>
    </div>
  </div>`);
}
```

```js
if (stintCohort.length > 0) {
  display(Plot.plot({
    width: 800,
    height: 300,
    marginLeft: 60,
    x: {
      label: "Stint Lap # (0=outlap)",
      domain: d3.range(0, Math.min(12, d3.max(stintCohort, d => d.stint_lap) + 1))
    },
    y: {
      label: "Delta from Car's Rep. Pace (s)",
      grid: true
    },
    marks: [
      // Zero reference line
      Plot.ruleY([0], {stroke: "#999", strokeDasharray: "4,4"}),
      // Range band (10th-90th percentile)
      Plot.areaY(stintCohort, {
        x: "stint_lap",
        y1: "minDelta",
        y2: "maxDelta",
        fill: "#457b9d",
        fillOpacity: 0.2,
        curve: "monotone-x"
      }),
      // Average line
      Plot.line(stintCohort, {
        x: "stint_lap",
        y: "avgDelta",
        stroke: "#e63946",
        strokeWidth: 2,
        curve: "monotone-x"
      }),
      // Median line
      Plot.line(stintCohort, {
        x: "stint_lap",
        y: "medianDelta",
        stroke: "#2a9d8f",
        strokeWidth: 2,
        strokeDasharray: "4,4",
        curve: "monotone-x"
      }),
      // Points
      Plot.dot(stintCohort, {
        x: "stint_lap",
        y: "avgDelta",
        fill: "#e63946",
        r: 5,
        tip: true,
        title: d => `Stint Lap ${d.stint_lap}\nAvg: ${d.avgDelta > 0 ? "+" : ""}${d.avgDelta.toFixed(2)}s\nMedian: ${d.medianDelta > 0 ? "+" : ""}${d.medianDelta.toFixed(2)}s\n10th-90th: ${d.minDelta.toFixed(2)}s to +${d.maxDelta.toFixed(2)}s\n(${d.count} samples)`
      })
    ]
  }));

  display(htl.html`<div class="note" style="margin-top: 0.5rem;">
    <span style="color: #e63946;">━━</span> Average delta
    <span style="color: #2a9d8f; margin-left: 1rem;">┈┈</span> Median delta
    <span style="color: #457b9d; margin-left: 1rem;">▒</span> 10th-90th percentile
    <span style="color: #999; margin-left: 1rem;">┈┈</span> Representative pace (0)
  </div>`);
} else {
  display(htl.html`<div class="note">Insufficient data for stint analysis (requires bpillar data from IMSA/WEC).</div>`);
}
```

## Recent Results

BPillar quartile averages filter out outliers (pit laps, cautions, traffic) for representative pace.

```js
Inputs.table(driverEvents.slice(0, 20), {
  columns: ["year", "event", "class", "car", "team", "laps", "best_lap", "avg_q1", "avg_q12"],
  header: {
    year: "Year",
    event: "Event",
    class: "Class",
    car: "Car #",
    team: "Team",
    laps: "Laps",
    best_lap: "Best",
    avg_q1: "Avg Top 25%",
    avg_q12: "Avg Top 50%"
  },
  format: {
    best_lap: d => d ? formatLapTime(d) : "-",
    avg_q1: d => d ? formatLapTime(d) : "-",
    avg_q12: d => d ? formatLapTime(d) : "-"
  },
  width: {
    year: 60,
    event: 120,
    class: 70,
    car: 50,
    team: 150,
    laps: 50,
    best_lap: 80,
    avg_q1: 95,
    avg_q12: 95
  }
})
```

<style>
.big {
  font-size: 1.5em;
  font-weight: bold;
}

/* Driver Hero Section */
.driver-hero {
  background: linear-gradient(135deg, var(--theme-background) 0%, color-mix(in srgb, var(--theme-foreground-focus) 8%, var(--theme-background)) 100%);
  border-radius: 12px;
  padding: 1.5rem;
  margin-bottom: 1.5rem;
  border: 1px solid var(--theme-foreground-faintest);
}

.driver-hero-main {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 2rem;
  margin-bottom: 1.25rem;
  padding-bottom: 1.25rem;
  border-bottom: 1px solid var(--theme-foreground-faintest);
}

.driver-identity {
  flex: 1;
}

.driver-name {
  font-size: 2rem;
  font-weight: 700;
  margin: 0 0 0.5rem 0;
  background: linear-gradient(135deg, var(--theme-foreground) 0%, var(--theme-foreground-focus) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.driver-badges {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}

.license-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 20px;
  color: white;
  font-size: 0.8rem;
  font-weight: 600;
}

.country-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 20px;
  background: var(--theme-foreground-faintest);
  color: var(--theme-foreground);
  font-size: 0.8rem;
}

.driver-team {
  color: var(--theme-foreground-muted);
  font-size: 0.9rem;
}

.driver-elo-display {
  display: flex;
  gap: 1.5rem;
  align-items: flex-end;
}

.elo-current {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.elo-value {
  font-size: 3rem;
  font-weight: 700;
  color: var(--theme-foreground-focus);
  line-height: 1;
}

.elo-label {
  font-size: 0.75rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.elo-trend {
  font-size: 0.85rem;
  font-weight: 600;
  padding: 0.15rem 0.5rem;
  border-radius: 4px;
  margin-top: 0.25rem;
}

.elo-trend.up {
  color: #2a9d8f;
  background: rgba(42, 157, 143, 0.1);
}

.elo-trend.down {
  color: #e63946;
  background: rgba(230, 57, 70, 0.1);
}

.elo-peak {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0.5rem 1rem;
  background: var(--theme-background-alt);
  border-radius: 8px;
}

.peak-value {
  font-size: 1.5rem;
  font-weight: 600;
  color: var(--theme-foreground);
}

.peak-label {
  font-size: 0.65rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
}

.driver-hero-stats {
  display: flex;
  gap: 2rem;
  justify-content: flex-start;
}

.hero-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 70px;
}

.stat-num {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--theme-foreground);
}

.stat-txt {
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
}

/* Career Stats Row */
.career-stats-row {
  display: flex;
  gap: 1.5rem;
  flex-wrap: wrap;
  margin-bottom: 1.5rem;
}

.career-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 1rem 1.5rem;
  background: var(--theme-background-alt);
  border-radius: 8px;
  min-width: 80px;
}

.career-stat.wins .career-stat-value {
  color: #ffd700;
}

.career-stat.podiums .career-stat-value {
  color: #2a9d8f;
}

.career-stat-value {
  font-size: 2rem;
  font-weight: 700;
  line-height: 1;
}

.career-stat-label {
  font-size: 0.7rem;
  color: var(--theme-foreground-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-top: 0.25rem;
}

@media (max-width: 768px) {
  .driver-hero-main {
    flex-direction: column;
    gap: 1rem;
  }

  .driver-elo-display {
    width: 100%;
    justify-content: space-between;
  }

  .elo-value {
    font-size: 2.5rem;
  }

  .career-stats-row {
    justify-content: center;
  }
}
</style>
