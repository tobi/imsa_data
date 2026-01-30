// Stat Card Component
// Reusable stat display card for overview statistics

/**
 * Creates a stat card element displaying a value with label and optional subtitle
 * @param {Object} options - Configuration options
 * @param {string} options.title - The title/label for the stat
 * @param {string|number} options.value - The main value to display
 * @param {string} [options.subtitle] - Optional subtitle text
 * @param {string} [options.trend] - Optional trend indicator (e.g., "+12" or "-5")
 * @param {boolean} [options.trendPositive] - Whether trend is positive (green) or negative (red)
 * @returns {HTMLElement} The stat card element
 */
export function statCard({title, value, subtitle, trend, trendPositive}) {
  const card = document.createElement("div");
  card.className = "stat-card";

  let html = `<h3>${escapeHtml(title)}</h3>`;
  html += `<div class="value">${escapeHtml(String(value))}`;

  if (trend !== undefined) {
    const trendClass = trendPositive ? "trend-positive" : "trend-negative";
    html += ` <span class="${trendClass}" style="font-size: 0.5em; color: ${trendPositive ? '#2a9d8f' : '#e63946'}">${escapeHtml(String(trend))}</span>`;
  }

  html += `</div>`;

  if (subtitle) {
    html += `<div class="subtitle">${escapeHtml(subtitle)}</div>`;
  }

  card.innerHTML = html;
  return card;
}

/**
 * Creates a grid of stat cards
 * @param {Array<Object>} stats - Array of stat configurations
 * @returns {HTMLElement} Grid container with stat cards
 */
export function statCardGrid(stats) {
  const grid = document.createElement("div");
  grid.className = "card-grid";

  for (const stat of stats) {
    grid.appendChild(statCard(stat));
  }

  return grid;
}

/**
 * Creates a license badge element
 * @param {string} license - License type (P, S, G, B, or name like Platinum, Silver, etc.)
 * @returns {HTMLElement} Badge element
 */
export function licenseBadge(license) {
  const badge = document.createElement("span");
  badge.className = "license-badge";

  // Normalize license to single letter code
  const licenseMap = {
    'platinum': 'p', 'p': 'p',
    'silver': 's', 's': 's',
    'gold': 'g', 'g': 'g',
    'bronze': 'b', 'b': 'b'
  };

  const code = licenseMap[license?.toLowerCase()] || 'l';
  badge.classList.add(`license-${code}`);

  const labels = {
    'p': 'Platinum',
    's': 'Silver',
    'g': 'Gold',
    'b': 'Bronze',
    'l': 'No License'
  };

  badge.textContent = labels[code];
  return badge;
}

/**
 * Creates a position badge element with medal styling for top 3
 * @param {number} position - Race position (1-based)
 * @returns {HTMLElement} Position badge element
 */
export function positionBadge(position) {
  const badge = document.createElement("span");
  badge.className = "position";

  if (position <= 3) {
    badge.classList.add(`position-${position}`);
  }

  badge.textContent = String(position);
  return badge;
}

// Utility function to escape HTML
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}
