import L from 'leaflet';

// OpenStreetMap tiles, greyed out in CSS (.map-frame .leaflet-tile-pane) so priority markers carry
// the colour. The public OSM tile servers are not for production traffic: pick a tile provider before launch.
export const TILE_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
export const TILE_ATTRIBUTION = '&copy; OpenStreetMap contributors';

export const PRIORITY_COLOR = { P1_CRITICAL: '#b3261e', P2_HIGH: '#c97a12', P3_VERIFY: '#5d6b7a' };
const MARKER_CLASS = { P1_CRITICAL: 'marker-critical', P2_HIGH: 'marker-high', P3_VERIFY: 'marker-check' };

export function incidentIcon(priority, selected = false) {
  const size = selected ? 18 : 14;
  return L.divIcon({
    className: '',
    html: `<div class="marker ${MARKER_CLASS[priority] || 'marker-check'}${selected ? ' is-selected' : ''}" style="width:${size}px;height:${size}px"></div>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
  });
}

export const CAMERA_ICON = L.divIcon({
  className: '',
  html: '<div class="marker-camera" style="width:11px;height:11px"></div>',
  iconSize: [11, 11],
  iconAnchor: [5, 5],
});

export const CONE_STYLE = { color: '#245e8c', weight: 1, fillColor: '#245e8c', fillOpacity: 0.1 };

/**
 * Field-of-view polygon in [lat, lng] for a camera at (lat, lng) facing azimuthDeg (clockwise from north).
 */
export function computeCameraFovCone(lat, lng, azimuthDeg = 180, fovDeg = 90, rangeMeters = 85) {
  const points = [[lat, lng]];
  const startAngle = azimuthDeg - fovDeg / 2;
  const endAngle = azimuthDeg + fovDeg / 2;
  const steps = 10;
  const metersPerDegLat = 111320;
  const metersPerDegLng = Math.max(1, 111320 * Math.cos((lat * Math.PI) / 180));
  for (let i = 0; i <= steps; i += 1) {
    const rad = ((startAngle + ((endAngle - startAngle) * i) / steps) * Math.PI) / 180;
    points.push([
      lat + (rangeMeters * Math.cos(rad)) / metersPerDegLat,
      lng + (rangeMeters * Math.sin(rad)) / metersPerDegLng,
    ]);
  }
  return points;
}
