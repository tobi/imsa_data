// Pill Filter Component
// Custom pill/tag style filters that work with Observable reactivity

/**
 * Creates a pill-style filter with multiple options
 * @param {Array<string>} options - Array of filter options
 * @param {Object} config - Configuration options
 * @param {string} [config.value] - Initial selected value (defaults to first option)
 * @param {string} [config.label] - Optional label to display before pills
 * @param {Object} [config.colors] - Optional color map for options {option: color}
 * @returns {HTMLElement} Interactive pill filter element
 */
export function pillFilter(options, config = {}) {
  const {value = options[0], label, colors = {}} = config;

  const container = document.createElement("div");
  container.className = "pill-filter";

  if (label) {
    const labelEl = document.createElement("span");
    labelEl.className = "pill-filter-label";
    labelEl.textContent = label;
    container.appendChild(labelEl);
  }

  const pillsContainer = document.createElement("div");
  pillsContainer.className = "pill-filter-options";

  let currentValue = value;

  options.forEach(option => {
    const pill = document.createElement("button");
    pill.type = "button";
    pill.className = "pill";
    pill.textContent = option;

    if (option === currentValue) {
      pill.classList.add("pill-active");
      if (colors[option]) {
        pill.style.setProperty("--pill-active-color", colors[option]);
      }
    }

    pill.addEventListener("click", () => {
      // Remove active from all pills
      pillsContainer.querySelectorAll(".pill").forEach(p => {
        p.classList.remove("pill-active");
        p.style.removeProperty("--pill-active-color");
      });

      // Activate clicked pill
      pill.classList.add("pill-active");
      if (colors[option]) {
        pill.style.setProperty("--pill-active-color", colors[option]);
      }

      currentValue = option;
      container.value = option;
      container.dispatchEvent(new CustomEvent("input", {bubbles: true}));
    });

    pillsContainer.appendChild(pill);
  });

  container.appendChild(pillsContainer);
  container.value = currentValue;

  return container;
}

/**
 * Creates a multi-select pill filter
 * @param {Array<string>} options - Array of filter options
 * @param {Object} config - Configuration options
 * @param {Array<string>} [config.value] - Initial selected values
 * @param {string} [config.label] - Optional label
 * @param {Object} [config.colors] - Optional color map
 * @returns {HTMLElement} Interactive multi-select pill filter
 */
export function pillFilterMulti(options, config = {}) {
  const {value = [], label, colors = {}} = config;

  const container = document.createElement("div");
  container.className = "pill-filter";

  if (label) {
    const labelEl = document.createElement("span");
    labelEl.className = "pill-filter-label";
    labelEl.textContent = label;
    container.appendChild(labelEl);
  }

  const pillsContainer = document.createElement("div");
  pillsContainer.className = "pill-filter-options";

  let currentValues = new Set(value);

  options.forEach(option => {
    const pill = document.createElement("button");
    pill.type = "button";
    pill.className = "pill";
    pill.textContent = option;

    if (currentValues.has(option)) {
      pill.classList.add("pill-active");
      if (colors[option]) {
        pill.style.setProperty("--pill-active-color", colors[option]);
      }
    }

    pill.addEventListener("click", () => {
      if (currentValues.has(option)) {
        currentValues.delete(option);
        pill.classList.remove("pill-active");
        pill.style.removeProperty("--pill-active-color");
      } else {
        currentValues.add(option);
        pill.classList.add("pill-active");
        if (colors[option]) {
          pill.style.setProperty("--pill-active-color", colors[option]);
        }
      }

      container.value = Array.from(currentValues);
      container.dispatchEvent(new CustomEvent("input", {bubbles: true}));
    });

    pillsContainer.appendChild(pill);
  });

  container.appendChild(pillsContainer);
  container.value = Array.from(currentValues);

  return container;
}
