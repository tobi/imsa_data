// Race Timeline Component
// Scrollable/zoomable timeline showing stints, pit stops, and FCY periods

import * as Plot from "npm:@observablehq/plot";
import * as d3 from "npm:d3";

// License colors per requirements
const LICENSE_COLORS = {
  Platinum: "#e63946",
  Gold: "#2a9d8f",
  Silver: "#457b9d",
  Bronze: "#e76f51",
  "": "#999999"
};

// Class colors for grouping
const CLASS_COLORS = {
  GTP: "#e63946",
  LMP2: "#457b9d",
  "GTD Pro": "#2a9d8f",
  GTDPRO: "#2a9d8f",
  GTDPro: "#2a9d8f",
  GTD: "#e9c46a",
  DPi: "#e63946",
  GTLM: "#2a9d8f",
  LMP3: "#9b5de5",
  HYPERCAR: "#e63946",
  LMGT3: "#e9c46a"
};

/**
 * Formats lap time in seconds to MM:SS.mmm or SS.mmm
 */
function formatLapTime(seconds) {
  if (seconds == null || isNaN(seconds)) return "-";
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (mins > 0) {
    return `${mins}:${secs.toFixed(3).padStart(6, "0")}`;
  }
  return secs.toFixed(3);
}

/**
 * Formats pace delta as +/- seconds
 */
function formatDelta(delta) {
  if (delta == null || isNaN(delta)) return "-";
  const sign = delta >= 0 ? "+" : "";
  return `${sign}${delta.toFixed(3)}s`;
}

/**
 * Extracts stint data from lap records
 * Groups consecutive laps by driver into stints with aggregated stats
 * Uses bpillar_quartile IN (1, 2) for representative pace per analysis rules
 */
function extractStints(laps, classBestPace) {
  // Group by car and stint_number
  const stintGroups = d3.groups(laps, d => d.car, d => d.stint_number);

  const stints = [];

  for (const [car, carStints] of stintGroups) {
    for (const [stintNum, stintLaps] of carStints) {
      if (stintLaps.length === 0) continue;

      const firstLap = stintLaps[0];
      const lastLap = stintLaps[stintLaps.length - 1];
      const stintClass = firstLap.class;

      // Use bpillar_quartile IN (1, 2) for representative pace
      // This excludes first lap, pit laps, cautions, traffic
      const representativeLaps = stintLaps.filter(d =>
        d.lap_time > 0 &&
        d.bpillar_quartile != null &&
        (d.bpillar_quartile === 1 || d.bpillar_quartile === 2)
      );

      // Fallback: if no bpillar data, use clean laps (no pit time, reasonable time)
      const cleanLaps = representativeLaps.length > 0
        ? representativeLaps
        : stintLaps.filter(d => d.lap_time > 0 && (!d.pit_time || d.pit_time <= 0));

      const lapTimes = cleanLaps.map(d => d.lap_time);
      const fastestLap = lapTimes.length > 0 ? d3.min(lapTimes) : null;
      const avgPace = lapTimes.length > 0 ? d3.mean(lapTimes) : null;

      // Calculate delta from class best pace
      const classBest = classBestPace?.[stintClass];
      const paceDelta = avgPace != null && classBest != null ? avgPace - classBest : null;
      const fastestDelta = fastestLap != null && classBest != null ? fastestLap - classBest : null;

      stints.push({
        car: car,
        class: stintClass,
        driver: firstLap.driver,
        license: firstLap.license || "",
        team: firstLap.team_name,
        stintNumber: stintNum,
        startLap: d3.min(stintLaps, d => d.lap),
        endLap: d3.max(stintLaps, d => d.lap),
        lapCount: stintLaps.length,
        cleanLapCount: cleanLaps.length,
        fastestLap: fastestLap,
        avgPace: avgPace,
        paceDelta: paceDelta,        // Delta from class best avg
        fastestDelta: fastestDelta,  // Delta from class best
        // For pit stop marker - check if last lap has pit time
        hasPitOut: lastLap.pit_time > 0,
        pitTime: lastLap.pit_time > 0 ? lastLap.pit_time : null
      });
    }
  }

  return stints;
}

/**
 * Calculates best representative pace per class
 * Uses bpillar_quartile IN (1, 2) for clean laps only
 */
function calculateClassBestPace(laps) {
  const classBest = {};

  // Get representative laps per class
  const byClass = d3.groups(laps, d => d.class);

  for (const [cls, classLaps] of byClass) {
    // Use bpillar_quartile IN (1, 2) for representative pace
    const representativeLaps = classLaps.filter(d =>
      d.lap_time > 0 &&
      d.bpillar_quartile != null &&
      (d.bpillar_quartile === 1 || d.bpillar_quartile === 2)
    );

    // Fallback if no bpillar data
    const cleanLaps = representativeLaps.length > 0
      ? representativeLaps
      : classLaps.filter(d => d.lap_time > 0 && (!d.pit_time || d.pit_time <= 0));

    if (cleanLaps.length > 0) {
      // Use Q1 average (top 25% of clean laps) as class reference
      const sortedTimes = cleanLaps.map(d => d.lap_time).sort((a, b) => a - b);
      const q1Count = Math.max(1, Math.floor(sortedTimes.length * 0.25));
      classBest[cls] = d3.mean(sortedTimes.slice(0, q1Count));
    }
  }

  return classBest;
}

/**
 * Extracts FCY (Full Course Yellow) periods from lap data
 * Looks for yellow/caution flags in the flags column
 */
function extractFCYPeriods(laps) {
  const periods = [];
  let currentPeriod = null;

  // Sort laps by lap number
  const sortedLaps = [...laps].sort((a, b) => a.lap - b.lap);

  // Get unique laps and check if any car had yellow flag
  const lapGroups = d3.groups(sortedLaps, d => d.lap);

  for (const [lapNum, lapData] of lapGroups) {
    // Check if any car had a yellow/caution flag
    const hasYellow = lapData.some(d => {
      const flags = (d.flags || "").toLowerCase();
      return flags.includes("yellow") ||
             flags.includes("caution") ||
             flags.includes("fcy") ||
             flags.includes("sc") ||  // Safety car
             flags === "y";
    });

    if (hasYellow) {
      if (!currentPeriod) {
        currentPeriod = { startLap: lapNum, endLap: lapNum };
      } else {
        currentPeriod.endLap = lapNum;
      }
    } else if (currentPeriod) {
      periods.push(currentPeriod);
      currentPeriod = null;
    }
  }

  // Don't forget the last period if it extends to the end
  if (currentPeriod) {
    periods.push(currentPeriod);
  }

  return periods;
}

/**
 * Extracts pit stops from lap data
 * Returns array of {car, lap, pitTime} for laps with pit_time > 0
 */
function extractPitStops(laps) {
  return laps
    .filter(d => d.pit_time && d.pit_time > 0)
    .map(d => ({
      car: d.car,
      class: d.class,
      lap: d.lap,
      pitTime: d.pit_time,
      driver: d.driver
    }));
}

/**
 * Creates a race timeline visualization using SVG
 * @param {Array<Object>} data - Array of lap records
 * @param {Object} options - Chart configuration
 * @returns {HTMLElement} The timeline element
 */
export function raceTimeline(data, options = {}) {
  const {
    width = 1200,
    height = 600,
    filterClass = null
  } = options;

  // Filter by class if specified
  let filteredData = filterClass
    ? data.filter(d => d.class === filterClass)
    : data;

  if (filteredData.length === 0) {
    const placeholder = document.createElement("div");
    placeholder.textContent = "No lap data available for timeline";
    placeholder.style.padding = "20px";
    placeholder.style.color = "#666";
    return placeholder;
  }

  // Calculate class best pace for delta comparisons
  const classBestPace = calculateClassBestPace(filteredData);

  // Extract data structures
  const stints = extractStints(filteredData, classBestPace);
  const fcyPeriods = extractFCYPeriods(filteredData);
  const pitStops = extractPitStops(filteredData);

  // Get unique cars grouped by class
  const carsByClass = d3.groups(
    [...new Set(filteredData.map(d => JSON.stringify({car: d.car, class: d.class})))]
      .map(s => JSON.parse(s)),
    d => d.class
  ).sort((a, b) => {
    // Sort classes in a sensible order
    const classOrder = ["GTP", "DPi", "HYPERCAR", "LMP2", "LMP3", "GTD Pro", "GTDPRO", "GTDPro", "GTLM", "GTD", "LMGT3"];
    const aIdx = classOrder.indexOf(a[0]) >= 0 ? classOrder.indexOf(a[0]) : 99;
    const bIdx = classOrder.indexOf(b[0]) >= 0 ? classOrder.indexOf(b[0]) : 99;
    return aIdx - bIdx;
  });

  // Flatten cars with class info for y-axis
  const cars = [];
  for (const [cls, classCars] of carsByClass) {
    // Sort cars within class by car number
    const sortedCars = classCars.sort((a, b) => {
      const numA = parseInt(a.car) || 0;
      const numB = parseInt(b.car) || 0;
      return numA - numB;
    });
    for (const carInfo of sortedCars) {
      cars.push({ car: carInfo.car, class: cls });
    }
  }

  const maxLap = d3.max(filteredData, d => d.lap);

  // Dimensions
  const marginTop = 40;
  const marginRight = 30;
  const marginBottom = 50;
  const marginLeft = 100;
  const rowHeight = 24;
  const actualHeight = Math.max(height, marginTop + marginBottom + cars.length * rowHeight);

  // Create container with scroll
  const container = document.createElement("div");
  container.style.width = `${width}px`;
  container.style.overflowX = "auto";
  container.style.overflowY = "auto";
  container.style.maxHeight = `${height}px`;
  container.style.border = "1px solid #ddd";
  container.style.borderRadius = "4px";
  container.style.backgroundColor = "#fafafa";

  // Scales
  const xScale = d3.scaleLinear()
    .domain([0, maxLap + 1])
    .range([marginLeft, width - marginRight]);

  const yScale = d3.scaleBand()
    .domain(cars.map(c => c.car))
    .range([marginTop, actualHeight - marginBottom])
    .padding(0.2);

  // Create SVG
  const svg = d3.create("svg")
    .attr("width", width)
    .attr("height", actualHeight)
    .attr("viewBox", [0, 0, width, actualHeight])
    .attr("style", "font: 10px sans-serif; background: white;");

  // Add FCY period bands (background)
  const fcyGroup = svg.append("g").attr("class", "fcy-periods");

  for (const period of fcyPeriods) {
    fcyGroup.append("rect")
      .attr("x", xScale(period.startLap - 0.5))
      .attr("y", marginTop)
      .attr("width", xScale(period.endLap + 0.5) - xScale(period.startLap - 0.5))
      .attr("height", actualHeight - marginTop - marginBottom)
      .attr("fill", "#fff3cd")
      .attr("opacity", 0.7);

    // Add FCY label at top
    fcyGroup.append("text")
      .attr("x", xScale((period.startLap + period.endLap) / 2))
      .attr("y", marginTop - 5)
      .attr("text-anchor", "middle")
      .attr("fill", "#856404")
      .attr("font-size", "9px")
      .text("FCY");
  }

  // Add class separator lines
  const classGroup = svg.append("g").attr("class", "class-separators");
  let lastClass = null;

  for (let i = 0; i < cars.length; i++) {
    if (cars[i].class !== lastClass && lastClass !== null) {
      const y = yScale(cars[i].car);
      classGroup.append("line")
        .attr("x1", marginLeft - 10)
        .attr("x2", width - marginRight)
        .attr("y1", y - yScale.step() * yScale.padding() / 2)
        .attr("y2", y - yScale.step() * yScale.padding() / 2)
        .attr("stroke", "#999")
        .attr("stroke-width", 1)
        .attr("stroke-dasharray", "4,2");
    }
    lastClass = cars[i].class;
  }

  // Add grid lines
  const gridGroup = svg.append("g").attr("class", "grid");

  // Vertical grid (every 10 laps)
  const lapTicks = d3.range(0, maxLap + 1, 10);
  for (const lap of lapTicks) {
    gridGroup.append("line")
      .attr("x1", xScale(lap))
      .attr("x2", xScale(lap))
      .attr("y1", marginTop)
      .attr("y2", actualHeight - marginBottom)
      .attr("stroke", "#eee")
      .attr("stroke-width", 1);
  }

  // Add stint boxes
  const stintGroup = svg.append("g").attr("class", "stints");

  // Create tooltip
  const tooltip = d3.select("body").append("div")
    .attr("class", "race-timeline-tooltip")
    .style("position", "absolute")
    .style("visibility", "hidden")
    .style("background", "rgba(0,0,0,0.85)")
    .style("color", "white")
    .style("padding", "8px 12px")
    .style("border-radius", "4px")
    .style("font-size", "11px")
    .style("pointer-events", "none")
    .style("z-index", "1000")
    .style("max-width", "250px")
    .style("box-shadow", "0 2px 8px rgba(0,0,0,0.3)");

  for (const stint of stints) {
    const y = yScale(stint.car);
    if (y === undefined) continue;

    const x1 = xScale(stint.startLap - 0.4);
    const x2 = xScale(stint.endLap + 0.4);
    const boxWidth = x2 - x1;
    const boxHeight = yScale.bandwidth();

    const licenseColor = LICENSE_COLORS[stint.license] || LICENSE_COLORS[""];

    // Stint box
    const stintRect = stintGroup.append("rect")
      .attr("x", x1)
      .attr("y", y)
      .attr("width", boxWidth)
      .attr("height", boxHeight)
      .attr("fill", licenseColor)
      .attr("opacity", 0.8)
      .attr("rx", 3)
      .attr("ry", 3)
      .attr("stroke", d3.color(licenseColor).darker(0.5))
      .attr("stroke-width", 1)
      .style("cursor", "pointer");

    // Hover effects
    stintRect
      .on("mouseover", function(event) {
        d3.select(this).attr("opacity", 1).attr("stroke-width", 2);
        // Show pace as delta from class best (per analysis rules)
        const paceDisplay = stint.paceDelta != null
          ? `${formatDelta(stint.paceDelta)} vs class`
          : formatLapTime(stint.avgPace);
        const fastestDisplay = stint.fastestDelta != null
          ? `${formatLapTime(stint.fastestLap)} (${formatDelta(stint.fastestDelta)})`
          : formatLapTime(stint.fastestLap);

        tooltip.style("visibility", "visible")
          .html(`
            <strong>#${stint.car} - ${stint.driver || "Unknown"}</strong><br/>
            <span style="color: ${licenseColor}">${stint.license || "No license"}</span> | ${stint.class}<br/>
            Laps ${stint.startLap}-${stint.endLap} (${stint.lapCount} laps, ${stint.cleanLapCount} clean)<br/>
            Fastest: ${fastestDisplay}<br/>
            Avg pace: ${paceDisplay}
            ${stint.pitTime ? `<br/>Pit: ${stint.pitTime.toFixed(1)}s` : ""}
          `);
      })
      .on("mousemove", function(event) {
        tooltip
          .style("top", (event.pageY - 10) + "px")
          .style("left", (event.pageX + 15) + "px");
      })
      .on("mouseout", function() {
        d3.select(this).attr("opacity", 0.8).attr("stroke-width", 1);
        tooltip.style("visibility", "hidden");
      });

    // Driver name inside box (if there's room)
    if (boxWidth > 40) {
      const driverName = stint.driver || "Unknown";
      // Truncate name to fit
      const maxChars = Math.floor(boxWidth / 6);
      const displayName = driverName.length > maxChars
        ? driverName.substring(0, maxChars - 1) + "…"
        : driverName;

      stintGroup.append("text")
        .attr("x", x1 + boxWidth / 2)
        .attr("y", y + boxHeight / 2)
        .attr("dy", "0.35em")
        .attr("text-anchor", "middle")
        .attr("fill", "white")
        .attr("font-size", "9px")
        .attr("font-weight", "500")
        .attr("pointer-events", "none")
        .text(displayName);
    }
  }

  // Add pit stop lines between stints
  const pitGroup = svg.append("g").attr("class", "pit-stops");

  for (const pit of pitStops) {
    const y = yScale(pit.car);
    if (y === undefined) continue;

    pitGroup.append("line")
      .attr("x1", xScale(pit.lap + 0.4))
      .attr("x2", xScale(pit.lap + 0.4))
      .attr("y1", y)
      .attr("y2", y + yScale.bandwidth())
      .attr("stroke", "#333")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "3,2");
  }

  // X-axis (laps)
  const xAxis = svg.append("g")
    .attr("transform", `translate(0,${actualHeight - marginBottom})`)
    .call(d3.axisBottom(xScale).ticks(Math.min(maxLap, 20)).tickFormat(d => `Lap ${d}`))
    .call(g => g.select(".domain").attr("stroke", "#999"))
    .call(g => g.selectAll(".tick line").attr("stroke", "#999"))
    .call(g => g.selectAll(".tick text").attr("fill", "#666"));

  // Y-axis (cars with class colors)
  const yAxis = svg.append("g")
    .attr("transform", `translate(${marginLeft},0)`)
    .call(d3.axisLeft(yScale).tickFormat(car => `#${car}`))
    .call(g => g.select(".domain").remove())
    .call(g => g.selectAll(".tick line").remove())
    .call(g => g.selectAll(".tick text")
      .attr("fill", car => {
        const carInfo = cars.find(c => c.car === car);
        return CLASS_COLORS[carInfo?.class] || "#666";
      })
      .attr("font-weight", "600"));

  // Add class labels on the left
  const classLabels = svg.append("g").attr("class", "class-labels");
  lastClass = null;
  let classStartY = marginTop;

  for (let i = 0; i <= cars.length; i++) {
    const currentClass = i < cars.length ? cars[i].class : null;

    if (currentClass !== lastClass && lastClass !== null) {
      const classEndY = i < cars.length ? yScale(cars[i].car) : actualHeight - marginBottom;
      const classMidY = (classStartY + classEndY) / 2;

      classLabels.append("text")
        .attr("x", 5)
        .attr("y", classMidY)
        .attr("dy", "0.35em")
        .attr("fill", CLASS_COLORS[lastClass] || "#666")
        .attr("font-size", "11px")
        .attr("font-weight", "700")
        .text(lastClass);

      classStartY = classEndY;
    }

    if (currentClass !== lastClass) {
      if (i < cars.length) {
        classStartY = yScale(cars[i].car);
      }
    }

    lastClass = currentClass;
  }

  // Title
  svg.append("text")
    .attr("x", width / 2)
    .attr("y", 15)
    .attr("text-anchor", "middle")
    .attr("fill", "#333")
    .attr("font-size", "14px")
    .attr("font-weight", "600")
    .text("Race Timeline - Stints by Driver");

  // Legend
  const legend = svg.append("g")
    .attr("transform", `translate(${width - 280}, 5)`);

  const licenses = ["Platinum", "Gold", "Silver", "Bronze"];
  licenses.forEach((license, i) => {
    legend.append("rect")
      .attr("x", i * 65)
      .attr("y", 0)
      .attr("width", 12)
      .attr("height", 12)
      .attr("fill", LICENSE_COLORS[license])
      .attr("rx", 2);

    legend.append("text")
      .attr("x", i * 65 + 16)
      .attr("y", 10)
      .attr("fill", "#666")
      .attr("font-size", "10px")
      .text(license);
  });

  container.appendChild(svg.node());

  // Cleanup tooltip on container removal
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.removedNodes) {
        if (node === container || node.contains?.(container)) {
          tooltip.remove();
          observer.disconnect();
          return;
        }
      }
    }
  });

  observer.observe(document.body, { childList: true, subtree: true });

  return container;
}

/**
 * Creates a compact race timeline using Observable Plot
 * Useful for smaller displays or quick overview
 */
export function raceTimelinePlot(data, options = {}) {
  const {
    width = 900,
    height = 400,
    filterClass = null
  } = options;

  let filteredData = filterClass
    ? data.filter(d => d.class === filterClass)
    : data;

  if (filteredData.length === 0) {
    const placeholder = document.createElement("div");
    placeholder.textContent = "No lap data available";
    return placeholder;
  }

  const classBestPace = calculateClassBestPace(filteredData);
  const stints = extractStints(filteredData, classBestPace);
  const fcyPeriods = extractFCYPeriods(filteredData);

  // Sort cars by class then number
  const cars = [...new Set(filteredData.map(d => d.car))].sort((a, b) => {
    const classA = filteredData.find(d => d.car === a)?.class || "";
    const classB = filteredData.find(d => d.car === b)?.class || "";
    if (classA !== classB) return classA.localeCompare(classB);
    return (parseInt(a) || 0) - (parseInt(b) || 0);
  });

  const maxLap = d3.max(filteredData, d => d.lap);

  const marks = [
    // FCY bands
    ...fcyPeriods.map(period =>
      Plot.rect([period], {
        x1: d => d.startLap - 0.5,
        x2: d => d.endLap + 0.5,
        y1: 0,
        y2: cars.length,
        fill: "#fff3cd",
        fillOpacity: 0.7
      })
    ),

    // Stint bars
    Plot.barX(stints, {
      x1: d => d.startLap - 0.4,
      x2: d => d.endLap + 0.4,
      y: "car",
      fill: d => LICENSE_COLORS[d.license] || LICENSE_COLORS[""],
      title: d => {
        const paceDisplay = d.paceDelta != null ? formatDelta(d.paceDelta) + " vs class" : formatLapTime(d.avgPace);
        return `#${d.car} ${d.driver}\n${d.license || "No license"} | ${d.class}\nLaps ${d.startLap}-${d.endLap} (${d.cleanLapCount} clean)\nFastest: ${formatLapTime(d.fastestLap)}\nAvg pace: ${paceDisplay}`;
      }
    }),

    // Pit stop markers
    Plot.tickX(stints.filter(d => d.hasPitOut), {
      x: d => d.endLap + 0.5,
      y: "car",
      stroke: "#333",
      strokeWidth: 2
    })
  ];

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    marginRight: 20,
    x: {
      label: "Lap",
      domain: [0, maxLap + 1]
    },
    y: {
      label: "Car",
      domain: cars
    },
    marks
  });
}

export { extractStints, extractFCYPeriods, extractPitStops, calculateClassBestPace, formatLapTime, formatDelta, LICENSE_COLORS, CLASS_COLORS };
