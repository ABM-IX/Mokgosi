# Responder console: design notes

- Two themes (light, dark, or follow the device) driven by CSS tokens in `src/style.css`. Preference saved in `localStorage` (guarded).
- Priority is shown by shape, glyph and wording as well as colour: critical = red circle "!", high = amber triangle "!", check = grey tick. Unacknowledged critical pins pulse; `prefers-reduced-motion` swaps the pulse for a static halo.
- Map first: queue on the left, city map in the centre, incident panel on the right. A red banner stays until every critical alert is acknowledged.
- Cameras: all opt-in, online cameras show on the city map (`GET /api/v1/cameras`, responders only, no stream addresses). Cameras within 150 m of the selected incident are highlighted and linked to it.
- Type: Inter (UI) and JetBrains Mono (ids, coordinates), self-hosted via fontsource.
- Map tiles default to CARTO Positron / Dark Matter. Check the provider's terms for production, or set `VITE_TILE_URL_LIGHT`, `VITE_TILE_URL_DARK` and `VITE_TILE_ATTRIBUTION`. OpenStreetMap's public tile servers are not for production traffic.
- Before/after screenshots: `docs/design/`.
