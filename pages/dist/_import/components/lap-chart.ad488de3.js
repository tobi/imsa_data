// Lap Time Chart Component
// Scatter/line chart for lap time analysis

import * as Plot from "../../_npm/@observablehq/plot@0.6.17/7c43807f.js";

// License colors for consistent theming
const LICENSE_COLORS = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51",
  "": "#9b5de5"
};

/**
 * Formats lap time in seconds to MM:SS.mmm or SS.mmm
 * @param {number} seconds - Lap time in seconds
 * @returns {string} Formatted lap time
 */
export function formatLapTime(seconds) {
  if (seconds == null || isNaN(seconds)) return "-";
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (mins > 0) {
    return `${mins}:${secs.toFixed(3).padStart(6, "0")}`;
  }
  return secs.toFixed(3);
}

/**
 * Creates a lap time scatter chart for a session
 * @param {Array<Object>} data - Array of lap records with lap, lap_time, driver, car
 * @param {Object} options - Chart configuration
 * @param {number} [options.width=800] - Chart width
 * @param {number} [options.height=400] - Chart height
 * @param {string} [options.colorBy='driver'] - Color by 'driver', 'car', 'license', or 'class'
 * @param {boolean} [options.showOutliers=true] - Whether to show outlier laps (pit stops, etc.)
 * @param {number} [options.maxLapTime] - Maximum lap time to display (filters outliers)
 * @returns {SVGElement} The chart SVG element
 */
export function lapTimeScatter(data, options = {}) {
  const {
    width = 800,
    height = 400,
    colorBy = "driver",
    showOutliers = true,
    maxLapTime
  } = options;

  // Filter out obvious outliers if requested
  let filteredData = data;
  if (!showOutliers || maxLapTime) {
    const times = data.map(d => d.lap_time).filter(t => t > 0).sort((a, b) => a - b);
    const median = times[Math.floor(times.length / 2)];
    const threshold = maxLapTime || median * 1.5;
    filteredData = data.filter(d => d.lap_time > 0 && d.lap_time <= threshold);
  }

  const colorConfig = colorBy === "license" ? {
    color: {
      domain: Object.keys(LICENSE_COLORS),
      range: Object.values(LICENSE_COLORS),
      legend: true
    }
  } : {
    color: {legend: true}
  };

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    marginRight: 120,
    x: {
      label: "Lap Number"
    },
    y: {
      label: "Lap Time (seconds)",
      reverse: true
    },
    ...colorConfig,
    marks: [
      Plot.dot(filteredData, {
        x: "lap",
        y: "lap_time",
        stroke: colorBy,
        fill: colorBy,
        fillOpacity: 0.5,
        r: 3,
        title: d => `${d.driver || d.car}\nLap ${d.lap}: ${formatLapTime(d.lap_time)}`
      }),
      Plot.tip(filteredData, Plot.pointer({
        x: "lap",
        y: "lap_time",
        title: d => `${d.driver || d.car}\nLap ${d.lap}\n${formatLapTime(d.lap_time)}`
      }))
    ]
  });
}

/**
 * Creates a lap time line chart showing progression for selected drivers/cars
 * @param {Array<Object>} data - Array of lap records
 * @param {Object} options - Chart configuration
 * @param {number} [options.width=800] - Chart width
 * @param {number} [options.height=400] - Chart height
 * @param {Array<string>} [options.drivers] - Specific drivers to highlight
 * @param {Array<string>} [options.cars] - Specific cars to highlight
 * @param {boolean} [options.smoothed=false] - Apply smoothing to lines
 * @returns {SVGElement} The chart SVG element
 */
export function lapTimeLine(data, options = {}) {
  const {
    width = 800,
    height = 400,
    drivers,
    cars,
    smoothed = false
  } = options;

  // Filter to selected drivers/cars if specified
  let filteredData = data;
  if (drivers && drivers.length > 0) {
    const driverSet = new Set(drivers.map(d => d.toLowerCase()));
    filteredData = data.filter(d => driverSet.has(d.driver?.toLowerCase()));
  } else if (cars && cars.length > 0) {
    const carSet = new Set(cars);
    filteredData = data.filter(d => carSet.has(d.car));
  }

  // Filter outliers
  const times = filteredData.map(d => d.lap_time).filter(t => t > 0).sort((a, b) => a - b);
  const median = times[Math.floor(times.length / 2)] || 90;
  filteredData = filteredData.filter(d => d.lap_time > 0 && d.lap_time <= median * 1.3);

  const curve = smoothed ? "catmull-rom" : "linear";

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    marginRight: 120,
    x: {
      label: "Lap Number"
    },
    y: {
      label: "Lap Time (seconds)",
      reverse: true
    },
    color: {legend: true},
    marks: [
      Plot.lineY(filteredData, {
        x: "lap",
        y: "lap_time",
        stroke: drivers ? "driver" : "car",
        strokeWidth: 1.5,
        curve
      }),
      Plot.tip(filteredData, Plot.pointer({
        x: "lap",
        y: "lap_time",
        title: d => `${d.driver || d.car}\nLap ${d.lap}\n${formatLapTime(d.lap_time)}`
      }))
    ]
  });
}

/**
 * Creates a lap time distribution histogram
 * @param {Array<Object>} data - Array of lap records
 * @param {Object} options - Chart configuration
 * @param {number} [options.width=600] - Chart width
 * @param {number} [options.height=300] - Chart height
 * @param {string} [options.driver] - Specific driver to analyze
 * @param {boolean} [options.showQuantiles=true] - Show quartile lines
 * @returns {SVGElement} The chart SVG element
 */
export function lapTimeDistribution(data, options = {}) {
  const {
    width = 600,
    height = 300,
    driver,
    showQuantiles = true
  } = options;

  let filteredData = driver
    ? data.filter(d => d.driver?.toLowerCase() === driver.toLowerCase())
    : data;

  // Filter out obvious pit laps
  const times = filteredData.map(d => d.lap_time).filter(t => t > 0).sort((a, b) => a - b);
  const median = times[Math.floor(times.length / 2)] || 90;
  filteredData = filteredData.filter(d => d.lap_time > 0 && d.lap_time <= median * 1.2);

  const marks = [
    Plot.rectY(filteredData, Plot.binX(
      {y: "count"},
      {
        x: "lap_time",
        fill: "#457b9d",
        thresholds: 30
      }
    )),
    Plot.ruleY([0])
  ];

  if (showQuantiles && filteredData.length > 0) {
    const sortedTimes = filteredData.map(d => d.lap_time).sort((a, b) => a - b);
    const q1 = sortedTimes[Math.floor(sortedTimes.length * 0.25)];
    const q2 = sortedTimes[Math.floor(sortedTimes.length * 0.5)];
    const q3 = sortedTimes[Math.floor(sortedTimes.length * 0.75)];

    marks.push(
      Plot.ruleX([q1], {stroke: "#2a9d8f", strokeWidth: 2, strokeDasharray: "4,4"}),
      Plot.ruleX([q2], {stroke: "#e63946", strokeWidth: 2}),
      Plot.ruleX([q3], {stroke: "#e76f51", strokeWidth: 2, strokeDasharray: "4,4"})
    );
  }

  return Plot.plot({
    width,
    height,
    marginLeft: 50,
    x: {
      label: "Lap Time (seconds)"
    },
    y: {
      label: "Count"
    },
    marks
  });
}

/**
 * Creates a sector time breakdown chart
 * @param {Array<Object>} data - Array of lap records with sector times
 * @param {Object} options - Chart configuration
 * @returns {SVGElement} The chart SVG element
 */
export function sectorBreakdown(data, options = {}) {
  const {
    width = 800,
    height = 300
  } = options;

  // Filter to laps with complete sector data
  const sectorData = data.filter(d =>
    d.lap_time_s1 > 0 && d.lap_time_s2 > 0 && d.lap_time_s3 > 0
  );

  if (sectorData.length === 0) {
    const placeholder = document.createElement("div");
    placeholder.textContent = "No sector data available";
    return placeholder;
  }

  // Transform to long format
  const longData = sectorData.flatMap(d => [
    {lap: d.lap, driver: d.driver, sector: "S1", time: d.lap_time_s1},
    {lap: d.lap, driver: d.driver, sector: "S2", time: d.lap_time_s2},
    {lap: d.lap, driver: d.driver, sector: "S3", time: d.lap_time_s3}
  ]);

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    x: {label: "Lap Number"},
    y: {label: "Sector Time (seconds)"},
    color: {
      domain: ["S1", "S2", "S3"],
      range: ["#e63946", "#457b9d", "#2a9d8f"],
      legend: true
    },
    marks: [
      Plot.lineY(longData, {
        x: "lap",
        y: "time",
        stroke: "sector",
        strokeWidth: 1.5
      })
    ]
  });
}
