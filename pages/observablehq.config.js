export default {
  title: "Motorsport DB",
  root: "src",
  output: "dist",
  theme: "dashboard",
  header: `<div style="display: flex; align-items: center; gap: 0.5rem;">
    <span style="font-weight: bold;">Motorsport DB</span>
  </div>`,
  footer: `Built with Observable Framework`,
  sidebar: true,
  toc: true,
  pager: true,
  pages: [
    {name: "Overview", path: "/"},
    {name: "Elo Ratings", path: "/elo"},
    {name: "Drivers", path: "/drivers/"},
    {name: "Teams", path: "/teams/"},
    {name: "Tracks", path: "/tracks/"},
    {name: "Events", path: "/events/"},
    {name: "Seasons", path: "/series/"},
    {name: "Compare", path: "/compare"}
  ]
};
