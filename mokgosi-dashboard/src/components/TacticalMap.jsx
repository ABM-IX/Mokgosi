import React from 'react';
import L from 'leaflet';
import {
  MapContainer,
  TileLayer,
  Marker,
  Popup,
  Circle,
  Polygon,
  Polyline,
} from 'react-leaflet';

function createIncidentIcon(priority) {
  const color =
    priority === 'P1_CRITICAL'
      ? '#e11d48'
      : priority === 'P2_HIGH'
      ? '#f59e0b'
      : '#0ea5e9';
  return L.divIcon({
    className: 'mokgosi-map-icon',
    html: `<div style="width:18px;height:18px;border-radius:50%;background:${color};border:3px solid #ffffff;box-shadow:0 0 0 6px ${color}55;"></div>`,
    iconSize: [18, 18],
    iconAnchor: [9, 9],
  });
}

const CAMERA_ICON = L.divIcon({
  className: 'mokgosi-cam-icon',
  html: `<div style="width:14px;height:14px;border-radius:4px;background:#10b981;border:2px solid #052e16;box-shadow:0 0 6px #10b981aa;"></div>`,
  iconSize: [14, 14],
  iconAnchor: [7, 7],
});

/**
 * Computes a directional Field-of-View (FOV) polygon in [lat, lng] coordinates
 * given a camera origin, azimuth (degrees clockwise from North), and FOV angle.
 */
export function computeCameraFovCone(lat, lng, azimuthDeg = 180, fovDeg = 90, rangeMeters = 85) {
  const points = [[lat, lng]];
  const startAngle = azimuthDeg - fovDeg / 2;
  const endAngle = azimuthDeg + fovDeg / 2;
  const steps = 10;
  const latRadians = (lat * Math.PI) / 180;
  const metersPerDegLat = 111320;
  const metersPerDegLng = Math.max(1, 111320 * Math.cos(latRadians));

  for (let i = 0; i <= steps; i += 1) {
    const angleDeg = startAngle + ((endAngle - startAngle) * i) / steps;
    const rad = (angleDeg * Math.PI) / 180;
    const dNorth = rangeMeters * Math.cos(rad);
    const dEast = rangeMeters * Math.sin(rad);
    points.push([lat + dNorth / metersPerDegLat, lng + dEast / metersPerDegLng]);
  }
  return points;
}

/**
 * Tactical Leaflet map displaying the latest incident position, live GPS
 * breadcrumb trail (`incident_locations`), 150m PostGIS search radius,
 * authorized cameras with directional FOV cones, and stream-modal triggers.
 */
export default function TacticalMap({
  incident,
  locations = [],
  cameras = [],
  onOpenCameraStream,
}) {
  if (!incident) return null;

  const trailPoints = [
    [Number(incident.lat), Number(incident.lng)],
    ...locations.map((loc) => [Number(loc.lat), Number(loc.lng)]),
  ];
  const latestPoint = trailPoints[trailPoints.length - 1] || [
    Number(incident.lat),
    Number(incident.lng),
  ];

  return (
    <div className="panel">
      <div className="panel-title-row">
        <h3>Tactical Location &amp; Authorized CCTV Mesh · 150m PostGIS Radius</h3>
        <small>
          Live trail points: {trailPoints.length} · Matched opt-in cameras: {cameras.length}
        </small>
      </div>

      <div className="map">
        <MapContainer
          key={`${incident.id}-${latestPoint[0]}-${latestPoint[1]}`}
          center={latestPoint}
          zoom={16}
          scrollWheelZoom={false}
        >
          <TileLayer
            attribution="&copy; OpenStreetMap contributors"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />

          <Circle
            center={latestPoint}
            radius={150}
            pathOptions={{ color: '#38bdf8', weight: 1.5, fillOpacity: 0.07 }}
          />

          {trailPoints.length > 1 && (
            <Polyline
              positions={trailPoints}
              pathOptions={{ color: '#f43f5e', weight: 3, dashArray: '6 4' }}
            />
          )}

          <Marker
            position={latestPoint}
            icon={createIncidentIcon(incident.priority)}
          >
            <Popup>
              <strong>{incident.trigger_type}</strong> ({incident.priority})
              <br />
              User: {incident.user_id}
              <br />
              GPS: {latestPoint[0].toFixed(5)}, {latestPoint[1].toFixed(5)}
            </Popup>
          </Marker>

          {cameras.map((cam) => {
            const cone = computeCameraFovCone(
              Number(cam.lat),
              Number(cam.lng),
              Number(cam.azimuth_deg ?? 180),
              Number(cam.fov_deg ?? 90),
            );
            return (
              <React.Fragment key={cam.id}>
                <Polygon
                  positions={cone}
                  pathOptions={{
                    color: '#10b981',
                    weight: 1,
                    fillColor: '#10b981',
                    fillOpacity: 0.22,
                  }}
                />
                <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={CAMERA_ICON}>
                  <Popup>
                    <strong>{cam.owner_name}</strong>
                    <br />
                    {Number(cam.distance_m || 0).toFixed(1)} m · Azimuth {cam.azimuth_deg}° · FOV{' '}
                    {cam.fov_deg}°
                  </Popup>
                </Marker>
              </React.Fragment>
            );
          })}
        </MapContainer>
      </div>

      <div className="camera-list">
        {cameras.length > 0 ? (
          cameras.map((cam) => (
            <div className="camera-card" key={cam.id}>
              <div>
                <b>{cam.owner_name}</b>
                <span>
                  {Number(cam.distance_m || 0).toFixed(1)} m · Azimuth {cam.azimuth_deg}° · FOV{' '}
                  {cam.fov_deg}°
                </span>
              </div>
              <button
                type="button"
                className="btn-camera"
                onClick={() => onOpenCameraStream(cam)}
              >
                Open Authorized Stream &amp; Snapshot
              </button>
            </div>
          ))
        ) : (
          <small>No authorized online opt-in cameras within 150m radius.</small>
        )}
      </div>
    </div>
  );
}

