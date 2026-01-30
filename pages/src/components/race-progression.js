// Race Progression Chart Component
// Full race lap-by-lap position visualization (bump chart style)

import * as Plot from "npm:@observablehq/plot";

// Class colors for IMSA
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
 * Calculates race positions from lap data
 * @param {Array<Object>} laps - Array of lap records with car, lap, session_time
 * @returns {Array<Object>} Array with car, lap, position, class
 */
function calculatePositions(laps) {
  // Group laps by lap number
  const lapGroups = new Map();
  for (const lap of laps) {
    if (!lapGroups.has(lap.lap)) {
      lapGroups.set(lap.lap, []);
    }
    lapGroups.get(lap.lap).push(lap);
  }

  const positions = [];

  for (const [lapNum, lapData] of lapGroups) {
    // Sort by cumulative time (or session_time) to determine position
    const sorted = [...lapData].sort((a, b) => {
      // Use session_time if available, otherwise cumulative
      const timeA = a.session_time || a.cumulative_time || 0;
      const timeB = b.session_time || b.cumulative_time || 0;
      return timeA - timeB;
    });

    sorted.forEach((lap, idx) => {
      positions.push({
        car: lap.car,
        driver: lap.driver,
        lap: lapNum,
        position: idx + 1,
        class: lap.class,
        team_name: lap.team_name
      });
    });
  }

  return positions;
}

/**
 * Calculates class-relative positions
 * @param {Array<Object>} laps - Array of lap records
 * @returns {Array<Object>} Array with class-relative positions
 */
function calculateClassPositions(laps) {
  const lapGroups = new Map();
  for (const lap of laps) {
    if (!lapGroups.has(lap.lap)) {
      lapGroups.set(lap.lap, []);
    }
    lapGroups.get(lap.lap).push(lap);
  }

  const positions = [];

  for (const [lapNum, lapData] of lapGroups) {
    // Group by class first
    const byClass = new Map();
    for (const lap of lapData) {
      if (!byClass.has(lap.class)) {
        byClass.set(lap.class, []);
      }
      byClass.get(lap.class).push(lap);
    }

    // Sort within each class
    for (const [cls, classLaps] of byClass) {
      const sorted = [...classLaps].sort((a, b) => {
        const timeA = a.session_time || a.cumulative_time || 0;
        const timeB = b.session_time || b.cumulative_time || 0;
        return timeA - timeB;
      });

      sorted.forEach((lap, idx) => {
        positions.push({
          car: lap.car,
          driver: lap.driver,
          lap: lapNum,
          position: idx + 1,
          class: cls,
          team_name: lap.team_name,
          classPosition: idx + 1
        });
      });
    }
  }

  return positions;
}

/**
 * Creates a race progression bump chart showing position changes over laps
 * @param {Array<Object>} data - Array of lap records or pre-calculated positions
 * @param {Object} options - Chart configuration
 * @param {number} [options.width=900] - Chart width
 * @param {number} [options.height=500] - Chart height
 * @param {Array<string>} [options.highlight] - Cars to highlight
 * @param {boolean} [options.byClass=false] - Show class-relative positions
 * @param {string} [options.filterClass] - Only show cars from this class
 * @returns {SVGElement} The chart SVG element
 */
export function raceProgression(data, options = {}) {
  const {
    width = 900,
    height = 500,
    highlight,
    byClass = false,
    filterClass
  } = options;

  // Check if data needs position calculation
  let positions = data;
  if (data.length > 0 && data[0].position === undefined) {
    positions = byClass ? calculateClassPositions(data) : calculatePositions(data);
  }

  // Filter by class if requested
  if (filterClass) {
    positions = positions.filter(d => d.class === filterClass);
  }

  // Get unique cars for legend
  const cars = [...new Set(positions.map(d => d.car))];
  const maxPosition = Math.max(...positions.map(d => byClass ? d.classPosition || d.position : d.position));

  // Highlight configuration
  const highlightSet = new Set(highlight || []);

  const marks = [
    // Grid lines for positions
    Plot.ruleY(
      Array.from({length: Math.min(maxPosition, 20)}, (_, i) => i + 1),
      {stroke: "#eee", strokeWidth: 1}
    ),
    // Position lines for each car
    Plot.line(positions, {
      x: "lap",
      y: byClass ? "classPosition" : "position",
      z: "car",
      stroke: d => {
        if (highlightSet.size > 0 && !highlightSet.has(d.car)) {
          return "#ddd";
        }
        return CLASS_COLORS[d.class] || "#999";
      },
      strokeWidth: d => highlightSet.size > 0 && highlightSet.has(d.car) ? 3 : 1.5,
      strokeOpacity: d => highlightSet.size > 0 && !highlightSet.has(d.car) ? 0.3 : 1,
      curve: "step"
    }),
    // Points at each lap
    Plot.dot(positions, {
      x: "lap",
      y: byClass ? "classPosition" : "position",
      fill: d => {
        if (highlightSet.size > 0 && !highlightSet.has(d.car)) {
          return "#ddd";
        }
        return CLASS_COLORS[d.class] || "#999";
      },
      r: 2,
      fillOpacity: d => highlightSet.size > 0 && !highlightSet.has(d.car) ? 0.3 : 0.8
    }),
    // Hover tips
    Plot.tip(positions, Plot.pointer({
      x: "lap",
      y: byClass ? "classPosition" : "position",
      title: d => `#${d.car} ${d.team_name || ''}\n${d.driver || ''}\nLap ${d.lap}: P${d.position}${d.classPosition ? ` (Class P${d.classPosition})` : ''}`
    }))
  ];

  // Add car labels at the end
  const lastLap = Math.max(...positions.map(d => d.lap));
  const finalPositions = positions.filter(d => d.lap === lastLap);

  marks.push(
    Plot.text(finalPositions, {
      x: d => lastLap + 1,
      y: byClass ? "classPosition" : "position",
      text: d => `#${d.car}`,
      fill: d => CLASS_COLORS[d.class] || "#999",
      fontSize: 10,
      textAnchor: "start"
    })
  );

  return Plot.plot({
    width,
    height,
    marginLeft: 40,
    marginRight: 60,
    x: {
      label: "Lap",
      domain: [1, lastLap + 2]
    },
    y: {
      label: byClass ? "Class Position" : "Overall Position",
      reverse: true,
      domain: [1, Math.min(maxPosition, 20) + 1]
    },
    marks
  });
}

/**
 * Creates a gap-to-leader chart showing time gaps over the race
 * @param {Array<Object>} data - Array of lap records with session_time
 * @param {Object} options - Chart configuration
 * @param {number} [options.width=900] - Chart width
 * @param {number} [options.height=400] - Chart height
 * @param {string} [options.leader] - Car number of the leader (uses actual leader if not specified)
 * @param {Array<string>} [options.cars] - Specific cars to show
 * @returns {SVGElement} The chart SVG element
 */
export function gapToLeader(data, options = {}) {
  const {
    width = 900,
    height = 400,
    leader,
    cars
  } = options;

  // Group by lap and find leader's time
  const lapGroups = new Map();
  for (const lap of data) {
    if (!lapGroups.has(lap.lap)) {
      lapGroups.set(lap.lap, []);
    }
    lapGroups.get(lap.lap).push(lap);
  }

  const gapData = [];

  for (const [lapNum, lapData] of lapGroups) {
    const sorted = [...lapData].sort((a, b) =>
      (a.session_time || 0) - (b.session_time || 0)
    );

    // Find leader (specified or actual)
    const leaderLap = leader
      ? sorted.find(d => d.car === leader)
      : sorted[0];

    if (!leaderLap) continue;

    const leaderTime = leaderLap.session_time || 0;

    for (const lap of sorted) {
      if (cars && !cars.includes(lap.car)) continue;

      const gap = (lap.session_time || 0) - leaderTime;
      gapData.push({
        car: lap.car,
        driver: lap.driver,
        class: lap.class,
        lap: lapNum,
        gap: gap
      });
    }
  }

  return Plot.plot({
    width,
    height,
    marginLeft: 60,
    marginRight: 80,
    x: {
      label: "Lap"
    },
    y: {
      label: "Gap to Leader (seconds)"
    },
    color: {
      legend: true
    },
    marks: [
      Plot.ruleY([0], {stroke: "#ccc"}),
      Plot.line(gapData, {
        x: "lap",
        y: "gap",
        stroke: "car",
        strokeWidth: 2
      }),
      Plot.tip(gapData, Plot.pointer({
        x: "lap",
        y: "gap",
        title: d => `#${d.car}\nLap ${d.lap}\nGap: ${d.gap.toFixed(1)}s`
      }))
    ]
  });
}

/**
 * Creates a pit stop timeline visualization
 * @param {Array<Object>} data - Array of lap records with pit_time
 * @param {Object} options - Chart configuration
 * @returns {SVGElement} The chart SVG element
 */
export function pitStopTimeline(data, options = {}) {
  const {
    width = 900,
    height = 300
  } = options;

  // Extract pit stops (laps with pit_time > 0)
  const pitStops = data.filter(d => d.pit_time && d.pit_time > 0);

  if (pitStops.length === 0) {
    const placeholder = document.createElement("div");
    placeholder.textContent = "No pit stop data available";
    return placeholder;
  }

  // Get unique cars
  const cars = [...new Set(pitStops.map(d => d.car))];

  return Plot.plot({
    width,
    height,
    marginLeft: 80,
    marginRight: 40,
    x: {
      label: "Lap"
    },
    y: {
      label: "Car",
      domain: cars
    },
    marks: [
      Plot.tickX(pitStops, {
        x: "lap",
        y: "car",
        stroke: d => CLASS_COLORS[d.class] || "#457b9d",
        strokeWidth: 3,
        title: d => `#${d.car}\nLap ${d.lap}\nPit Time: ${d.pit_time.toFixed(1)}s`
      }),
      Plot.tip(pitStops, Plot.pointer({
        x: "lap",
        y: "car",
        title: d => `#${d.car}\nLap ${d.lap}\nPit: ${d.pit_time.toFixed(1)}s`
      }))
    ]
  });
}

export { calculatePositions, calculateClassPositions };
