// Elo Progression Chart Component
// Line chart showing driver Elo ratings over time with multi-driver overlay

import * as Plot from "../../_npm/@observablehq/plot@0.6.17/7c43807f.js";

// License colors for consistent theming
const LICENSE_COLORS = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51",
  "": "#9b5de5"
};

// Class colors for IMSA
const CLASS_COLORS = {
  GTP: "#e63946",
  LMP2: "#457b9d",
  "GTD Pro": "#2a9d8f",
  GTD: "#e9c46a",
  DPi: "#e63946",
  GTLM: "#2a9d8f"
};

/**
 * Creates an Elo progression line chart for one or more drivers
 * @param {Array<Object>} data - Array of Elo history records with driver, session_date, elo, license
 * @param {Object} options - Chart configuration options
 * @param {number} [options.width=800] - Chart width
 * @param {number} [options.height=400] - Chart height
 * @param {Array<string>} [options.drivers] - Specific drivers to show (shows all if not specified)
 * @param {boolean} [options.showDelta=false] - Show Elo change markers
 * @param {string} [options.colorBy='driver'] - Color by 'driver', 'license', or 'class'
 * @returns {SVGElement} The chart SVG element
 */
export function eloChart(data, options = {}) {
  const {
    width = 800,
    height = 400,
    drivers,
    showDelta = false,
    colorBy = "driver"
  } = options;

  // Filter to specific drivers if requested
  let filteredData = data;
  if (drivers && drivers.length > 0) {
    const driverSet = new Set(drivers.map(d => d.toLowerCase()));
    filteredData = data.filter(d => driverSet.has(d.driver?.toLowerCase()));
  }

  // Parse dates if needed
  filteredData = filteredData.map(d => ({
    ...d,
    date: d.session_date instanceof Date ? d.session_date : new Date(d.session_date)
  }));

  // Determine color scheme
  let colorConfig;
  if (colorBy === "license") {
    colorConfig = {
      color: {
        domain: Object.keys(LICENSE_COLORS),
        range: Object.values(LICENSE_COLORS),
        legend: true
      }
    };
  } else if (colorBy === "class") {
    colorConfig = {
      color: {
        domain: Object.keys(CLASS_COLORS),
        range: Object.values(CLASS_COLORS),
        legend: true
      }
    };
  } else {
    colorConfig = {
      color: {
        legend: true
      }
    };
  }

  const marks = [
    Plot.ruleY([1500], {stroke: "#ccc", strokeDasharray: "4,4"}),
    Plot.lineY(filteredData, {
      x: "date",
      y: "elo",
      stroke: colorBy === "driver" ? "driver" : colorBy,
      strokeWidth: 2,
      curve: "step-after"
    }),
    Plot.tip(filteredData, Plot.pointer({
      x: "date",
      y: "elo",
      title: d => `${d.driver}\n${d.event}\n${d.session_date}\nElo: ${d.elo}${d.delta ? ` (${d.delta > 0 ? '+' : ''}${d.delta})` : ''}`
    }))
  ];

  if (showDelta) {
    marks.push(
      Plot.dot(filteredData.filter(d => Math.abs(d.delta || 0) >= 10), {
        x: "date",
        y: "elo",
        fill: d => (d.delta || 0) >= 0 ? "#2a9d8f" : "#e63946",
        r: 4,
        title: d => `${d.delta > 0 ? '+' : ''}${d.delta}`
      })
    );
  }

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    marginRight: 120,
    x: {
      type: "time",
      label: "Date"
    },
    y: {
      label: "Elo Rating",
      domain: [
        Math.min(1200, Math.min(...filteredData.map(d => d.elo)) - 50),
        Math.max(1800, Math.max(...filteredData.map(d => d.elo)) + 50)
      ]
    },
    ...colorConfig,
    marks
  });
}

/**
 * Creates a small Elo sparkline chart for inline display
 * @param {Array<Object>} data - Elo history records for a single driver
 * @param {Object} options - Chart options
 * @param {number} [options.width=150] - Chart width
 * @param {number} [options.height=40] - Chart height
 * @returns {SVGElement} The sparkline SVG element
 */
export function eloSparkline(data, options = {}) {
  const {width = 150, height = 40} = options;

  const sortedData = [...data]
    .map(d => ({
      ...d,
      date: d.session_date instanceof Date ? d.session_date : new Date(d.session_date)
    }))
    .sort((a, b) => a.date - b.date);

  if (sortedData.length === 0) {
    return document.createElement("span");
  }

  const lastElo = sortedData[sortedData.length - 1].elo;
  const firstElo = sortedData[0].elo;
  const trend = lastElo - firstElo;

  return Plot.plot({
    width,
    height,
    axis: null,
    margin: 0,
    marks: [
      Plot.areaY(sortedData, {
        x: "date",
        y: "elo",
        fill: trend >= 0 ? "#2a9d8f" : "#e63946",
        fillOpacity: 0.2,
        curve: "step-after"
      }),
      Plot.lineY(sortedData, {
        x: "date",
        y: "elo",
        stroke: trend >= 0 ? "#2a9d8f" : "#e63946",
        strokeWidth: 1.5,
        curve: "step-after"
      })
    ]
  });
}

/**
 * Creates an Elo distribution histogram
 * @param {Array<Object>} data - Array of current ratings with driver, elo, license
 * @param {Object} options - Chart options
 * @param {number} [options.width=600] - Chart width
 * @param {number} [options.height=300] - Chart height
 * @param {boolean} [options.byLicense=true] - Color bars by license type
 * @returns {SVGElement} The histogram SVG element
 */
export function eloDistribution(data, options = {}) {
  const {
    width = 600,
    height = 300,
    byLicense = true
  } = options;

  const colorConfig = byLicense ? {
    color: {
      domain: Object.keys(LICENSE_COLORS),
      range: Object.values(LICENSE_COLORS),
      legend: true
    }
  } : {};

  return Plot.plot({
    width,
    height,
    marginLeft: 50,
    x: {
      label: "Elo Rating",
      domain: [1200, 1900]
    },
    y: {
      label: "Drivers"
    },
    ...colorConfig,
    marks: [
      Plot.rectY(data, Plot.binX(
        {y: "count"},
        {
          x: "elo",
          fill: byLicense ? "license" : "#457b9d",
          thresholds: 20
        }
      )),
      Plot.ruleY([0])
    ]
  });
}
