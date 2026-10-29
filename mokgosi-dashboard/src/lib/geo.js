// Small map helpers. Everything here is pure so it can be tested without a browser.

const EARTH_RADIUS_M = 6371008.8;

/** Great-circle distance in metres between two [lat, lng] points. */
export function distanceMeters(lat1, lng1, lat2, lng2) {
  const rad = (deg) => (Number(deg) * Math.PI) / 180;
  const dLat = rad(lat2) - rad(lat1);
  const dLng = rad(lng2) - rad(lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Only cameras that are consented and online ever reach the map. */
export function isUsableCamera(camera) {
  return camera?.is_authorized !== false && (camera?.connection_status || 'ONLINE') === 'ONLINE';
}

/**
 * Cameras within `radiusM` of a point, nearest first, each with a fresh `distance_m`.
 * The server enforces the same 150 m rule before it will sign a snapshot; this only decides what to highlight.
 */
export function camerasNear(cameras, lat, lng, radiusM = 150) {
  if (lat == null || lng == null) return [];
  return cameras
    .filter(isUsableCamera)
    .map((camera) => ({ ...camera, distance_m: distanceMeters(lat, lng, camera.lat, camera.lng) }))
    .filter((camera) => camera.distance_m <= radiusM)
    .sort((a, b) => a.distance_m - b.distance_m);
}

/** Field-of-view wedge as [lat, lng] points for a camera facing `azimuthDeg` (clockwise from north). */
export function fovCone(lat, lng, azimuthDeg = 180, fovDeg = 90, rangeMeters = 85) {
  const points = [[lat, lng]];
  const start = azimuthDeg - fovDeg / 2;
  const steps = 12;
  const metersPerDegLat = 111320;
  const metersPerDegLng = Math.max(1, 111320 * Math.cos((lat * Math.PI) / 180));
  for (let i = 0; i <= steps; i += 1) {
    const rad = ((start + (fovDeg * i) / steps) * Math.PI) / 180;
    points.push([lat + (rangeMeters * Math.cos(rad)) / metersPerDegLat, lng + (rangeMeters * Math.sin(rad)) / metersPerDegLng]);
  }
  return points;
}
