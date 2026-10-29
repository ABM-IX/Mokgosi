import L from 'leaflet';
import { fovCone } from './geo.js';

// Map tiles. CARTO's Positron and Dark Matter match the console's two themes. These are third-party
// services with their own usage terms, so check them (or swap in your own provider through the two
// VITE_TILE_URL_* variables) before this goes anywhere near real traffic.
const TILE_LIGHT = import.meta.env.VITE_TILE_URL_LIGHT || 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const TILE_DARK = import.meta.env.VITE_TILE_URL_DARK || 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
export const TILE_ATTRIBUTION =
  import.meta.env.VITE_TILE_ATTRIBUTION || '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>';

export function tileFor(resolvedTheme) {
  return { url: resolvedTheme === 'dark' ? TILE_DARK : TILE_LIGHT, attribution: TILE_ATTRIBUTION, subdomains: 'abcd' };
}

export const PRIORITY_COLOR = { P1_CRITICAL: '#e5383b', P2_HIGH: '#f08c00', P3_VERIFY: '#7b8794' };
export const ACCENT = '#3b82c4';

const COVERT = new Set(['DURESS_PIN', 'COVERT_SOS', 'SHAKE_SOS']);

// Shape and glyph carry the priority as well as colour, so a map is readable without telling red from amber.
const GLYPH = {
  P1_CRITICAL:
    '<circle cx="16" cy="16" r="13" class="pin-fill"/><path d="M16 9.5v9" stroke="#fff" stroke-width="3" stroke-linecap="round"/><circle cx="16" cy="23" r="1.9" fill="#fff"/>',
  P2_HIGH:
    '<path d="M16 4.2 28.6 26.2H3.4Z" class="pin-fill" stroke-linejoin="round" stroke-width="3"/><path d="M16 12.5v6.2" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/><circle cx="16" cy="22.4" r="1.6" fill="#fff"/>',
  P3_VERIFY:
    '<circle cx="16" cy="16" r="12" class="pin-fill"/><path d="M10.6 16.4l3.8 3.8 7-7.6" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>',
};
const PIN_CLASS = { P1_CRITICAL: 'pin-critical', P2_HIGH: 'pin-high', P3_VERIFY: 'pin-check' };

/**
 * Marker for one incident. A critical alert nobody has acknowledged yet keeps a pulsing ring (static under
 * reduced motion); a silent alert carries a purple "do not contact" badge.
 */
export function incidentIcon(incident, selected = false) {
  const priority = incident?.priority in GLYPH ? incident.priority : 'P3_VERIFY';
  const unacked = priority === 'P1_CRITICAL' && incident?.status === 'CREATED';
  const covert = COVERT.has(incident?.trigger_type);
  const classes = ['pin', PIN_CLASS[priority], unacked ? 'is-unacked' : '', selected ? 'is-selected' : ''].filter(Boolean).join(' ');
  const html =
    `<div class="${classes}"><span class="pin-ring"></span>` +
    `<svg viewBox="0 0 32 32" width="34" height="34" aria-hidden="true">${GLYPH[priority]}</svg>` +
    (covert ? '<span class="pin-badge" title="Silent alert: do not contact"><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.6 2.6l6.8 6.8" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg></span>' : '') +
    '</div>';
  return L.divIcon({ className: 'pin-host', html, iconSize: [34, 34], iconAnchor: [17, 17], popupAnchor: [0, -16] });
}

const CAMERA_SVG =
  '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>';

/** `near` cameras (inside the selected incident's 150 m) are bright; the rest of the registry is quieter. */
export function cameraIcon(near = false) {
  return L.divIcon({
    className: 'pin-host',
    html: `<div class="cam ${near ? 'is-near' : ''}">${CAMERA_SVG}</div>`,
    iconSize: [26, 26],
    iconAnchor: [13, 13],
    popupAnchor: [0, -12],
  });
}

export function coneStyle(near) {
  return near
    ? { color: ACCENT, weight: 1.2, fillColor: ACCENT, fillOpacity: 0.22, interactive: false }
    : { color: ACCENT, weight: 0.8, fillColor: ACCENT, fillOpacity: 0.07, opacity: 0.5, interactive: false };
}

export { fovCone as computeCameraFovCone };
