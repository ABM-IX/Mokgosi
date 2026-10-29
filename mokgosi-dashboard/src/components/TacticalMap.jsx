import React from 'react';
import { Circle, MapContainer, Marker, Polygon, Polyline, Popup, TileLayer } from 'react-leaflet';
import { PRIORITY_LABEL, TRIGGER_LABEL, coords, label } from '../lib/labels.js';
import { PRIORITY_COLOR, cameraIcon, computeCameraFovCone, coneStyle, incidentIcon, tileFor } from '../lib/mapStyle.js';

/** One incident: where it started, the trail since, the 150 m search circle and opt-in cameras in it. */
export default function TacticalMap({ incident, locations = [], cameras = [], onOpenCameraStream, theme = 'light' }) {
  if (!incident) return null;

  const trailPoints = [
    [Number(incident.lat), Number(incident.lng)],
    ...locations.map((loc) => [Number(loc.lat), Number(loc.lng)]),
  ];
  const latestPoint = trailPoints[trailPoints.length - 1];
  const color = PRIORITY_COLOR[incident.priority] || PRIORITY_COLOR.P3_VERIFY;
  const tiles = tileFor(theme);

  return (
    <section className="card" aria-label="Location">
      <div className="card-head">
        <h2>Location and nearby cameras</h2>
        <span className="card-note">
          {trailPoints.length > 1 ? `${trailPoints.length} location updates · ` : ''}
          Opt-in cameras within 150 m
        </span>
      </div>

      <div className="map-frame">
        <MapContainer key={`${incident.id}-${latestPoint[0]}-${latestPoint[1]}`} center={latestPoint} zoom={16} scrollWheelZoom={false}>
          <TileLayer key={theme} url={tiles.url} attribution={tiles.attribution} subdomains={tiles.subdomains} />
          <Circle center={latestPoint} radius={150} pathOptions={{ color, weight: 1, dashArray: '4 5', fillOpacity: 0.05 }} />
          {trailPoints.length > 1 && <Polyline positions={trailPoints} pathOptions={{ color, weight: 2.5, opacity: 0.8 }} />}
          <Marker position={latestPoint} icon={incidentIcon(incident, true)} zIndexOffset={2000}>
            <Popup>
              <div className="map-popup">
                <strong>{label(TRIGGER_LABEL, incident.trigger_type)}</strong>
                <span className="muted">{label(PRIORITY_LABEL, incident.priority)}</span>
                <span className="mono">{coords(latestPoint[0], latestPoint[1], 5)}</span>
              </div>
            </Popup>
          </Marker>
          {cameras.map((cam) => (
            <React.Fragment key={cam.id}>
              <Polygon
                positions={computeCameraFovCone(Number(cam.lat), Number(cam.lng), Number(cam.azimuth_deg ?? 180), Number(cam.fov_deg ?? 90))}
                pathOptions={coneStyle(true)}
              />
              <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={cameraIcon(true)}>
                <Popup>
                  <div className="map-popup">
                    <strong>{cam.owner_name}</strong>
                    <span className="muted">{Number(cam.distance_m || 0).toFixed(0)} m away</span>
                  </div>
                </Popup>
              </Marker>
            </React.Fragment>
          ))}
        </MapContainer>
      </div>

      {cameras.length > 0 ? (
        <ul className="camera-list">
          {cameras.map((cam) => (
            <li key={cam.id}>
              <span>
                {cam.owner_name}
                <span className="faint"> · {Number(cam.distance_m || 0).toFixed(0)} m away</span>
              </span>
              <button type="button" className="btn btn-small" onClick={() => onOpenCameraStream(cam)}>
                View camera
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="card-note">No opt-in cameras are online within 150 m.</p>
      )}
    </section>
  );
}
