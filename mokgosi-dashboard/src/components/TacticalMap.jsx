import React from 'react';
import { Circle, MapContainer, Marker, Polygon, Polyline, Popup, TileLayer } from 'react-leaflet';
import { PRIORITY_LABEL, TRIGGER_LABEL, coords, label } from '../lib/labels.js';
import {
  CAMERA_ICON,
  CONE_STYLE,
  PRIORITY_COLOR,
  TILE_ATTRIBUTION,
  TILE_URL,
  computeCameraFovCone,
  incidentIcon,
} from '../lib/mapStyle.js';

/** One incident: where it started, the trail since, the 150 m search circle and opt-in cameras in it. */
export default function TacticalMap({ incident, locations = [], cameras = [], onOpenCameraStream }) {
  if (!incident) return null;

  const trailPoints = [
    [Number(incident.lat), Number(incident.lng)],
    ...locations.map((loc) => [Number(loc.lat), Number(loc.lng)]),
  ];
  const latestPoint = trailPoints[trailPoints.length - 1];
  const color = PRIORITY_COLOR[incident.priority] || PRIORITY_COLOR.P3_VERIFY;

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
        <MapContainer
          key={`${incident.id}-${latestPoint[0]}-${latestPoint[1]}`}
          center={latestPoint}
          zoom={16}
          scrollWheelZoom={false}
        >
          <TileLayer attribution={TILE_ATTRIBUTION} url={TILE_URL} />
          <Circle center={latestPoint} radius={150} pathOptions={{ color, weight: 1, dashArray: '4 4', fillOpacity: 0.04 }} />
          {trailPoints.length > 1 && <Polyline positions={trailPoints} pathOptions={{ color, weight: 2.5, opacity: 0.8 }} />}
          <Marker position={latestPoint} icon={incidentIcon(incident.priority, true)}>
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
                pathOptions={CONE_STYLE}
              />
              <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={CAMERA_ICON}>
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
