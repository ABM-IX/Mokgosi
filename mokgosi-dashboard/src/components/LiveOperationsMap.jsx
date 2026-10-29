import React, { useEffect, useMemo, useState } from 'react';
import { Circle, MapContainer, Marker, Polygon, Popup, TileLayer, useMap } from 'react-leaflet';
import { isGbvIncident } from './IncidentQueue.jsx';
import {
  NEXT_ACTION_LABEL,
  PRIORITY_LABEL,
  STATUS_LABEL,
  TRIGGER_LABEL,
  label,
  shortId,
  timeAgo,
} from '../lib/labels.js';
import {
  CAMERA_ICON,
  CONE_STYLE,
  PRIORITY_COLOR,
  TILE_ATTRIBUTION,
  TILE_URL,
  computeCameraFovCone,
  incidentIcon,
} from '../lib/mapStyle.js';

const GABORONE_CBD = [-24.656, 25.912];
const PRIORITY_FILTERS = [
  ['ALL', 'All'],
  ['P1_CRITICAL', 'Critical'],
  ['P2_HIGH', 'High'],
  ['P3_VERIFY', 'Check'],
];

function MapViewController({ center, zoom }) {
  const map = useMap();
  useEffect(() => {
    if (center && map) map.setView(center, zoom, { animate: true });
  }, [center, zoom, map]);
  return null;
}

/** Every open incident of the current type on one map, with quick actions in each popup. */
export default function LiveOperationsMap({
  incidents = [],
  selectedId = null,
  onSelectIncident,
  onLifecycle,
  cameras = [],
  onOpenCameraStream,
  activePillar = 'ALL',
}) {
  const [priorityFilter, setPriorityFilter] = useState('ALL');
  const [showCameras, setShowCameras] = useState(true);
  const [showRadii, setShowRadii] = useState(true);
  const [mapCenter, setMapCenter] = useState(GABORONE_CBD);
  const [mapZoom, setMapZoom] = useState(14);

  useEffect(() => {
    const target = selectedId && incidents.find((i) => i.id === selectedId);
    if (target && target.lat && target.lng) {
      setMapCenter([Number(target.lat), Number(target.lng)]);
      setMapZoom(15);
    }
  }, [selectedId, incidents]);

  const open = useMemo(
    () =>
      incidents.filter((inc) => {
        if (!inc.lat || !inc.lng || inc.status === 'RESOLVED') return false;
        if (activePillar === 'SAFER_COMMUNITIES' && isGbvIncident(inc)) return false;
        if (activePillar === 'GBV_RESPONSE' && !isGbvIncident(inc)) return false;
        return true;
      }),
    [incidents, activePillar],
  );
  const shown = priorityFilter === 'ALL' ? open : open.filter((inc) => inc.priority === priorityFilter);
  const countFor = (key) => (key === 'ALL' ? open.length : open.filter((inc) => inc.priority === key).length);

  return (
    <section className="card" aria-label="City map">
      <div className="card-head">
        <h2>City map</h2>
        <span className="card-note">{shown.length} open incidents shown</span>
      </div>

      <div className="map-toolbar" role="toolbar" aria-label="Map options">
        <div className="filter-group" aria-label="Priority">
          <span className="faint">Priority</span>
          {PRIORITY_FILTERS.map(([key, text]) => (
            <button
              key={key}
              type="button"
              className="chip"
              aria-pressed={priorityFilter === key}
              onClick={() => setPriorityFilter(key)}
            >
              {text} {countFor(key)}
            </button>
          ))}
        </div>
        <div className="filter-group">
          <label className="check-label">
            <input type="checkbox" checked={showCameras} onChange={(e) => setShowCameras(e.target.checked)} />
            Cameras ({cameras.length})
          </label>
          <label className="check-label">
            <input type="checkbox" checked={showRadii} onChange={(e) => setShowRadii(e.target.checked)} />
            150 m circles
          </label>
          <button
            type="button"
            className="btn btn-small"
            onClick={() => {
              setMapCenter([...GABORONE_CBD]);
              setMapZoom(14);
            }}
          >
            Recenter
          </button>
        </div>
      </div>

      <div className="map-frame is-tall">
        <MapContainer center={mapCenter} zoom={mapZoom} scrollWheelZoom>
          <MapViewController center={mapCenter} zoom={mapZoom} />
          <TileLayer attribution={TILE_ATTRIBUTION} url={TILE_URL} />

          {showRadii &&
            shown.map((inc) => (
              <Circle
                key={`radius-${inc.id}`}
                center={[Number(inc.lat), Number(inc.lng)]}
                radius={150}
                pathOptions={{
                  color: PRIORITY_COLOR[inc.priority] || PRIORITY_COLOR.P3_VERIFY,
                  weight: 1,
                  fillOpacity: 0.04,
                  dashArray: inc.id === selectedId ? undefined : '4 4',
                }}
              />
            ))}

          {showCameras &&
            cameras.map((cam) => (
              <React.Fragment key={`cam-${cam.id}`}>
                <Polygon
                  positions={computeCameraFovCone(Number(cam.lat), Number(cam.lng), Number(cam.azimuth_deg ?? 180), Number(cam.fov_deg ?? 90), 90)}
                  pathOptions={CONE_STYLE}
                />
                <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={CAMERA_ICON}>
                  <Popup>
                    <div className="map-popup">
                      <strong>{cam.owner_name}</strong>
                      <span className="muted">Opt-in camera</span>
                      {onOpenCameraStream && (
                        <button type="button" className="btn btn-small" onClick={() => onOpenCameraStream(cam)}>
                          View camera
                        </button>
                      )}
                    </div>
                  </Popup>
                </Marker>
              </React.Fragment>
            ))}

          {shown.map((inc) => (
            <Marker
              key={`inc-${inc.id}`}
              position={[Number(inc.lat), Number(inc.lng)]}
              icon={incidentIcon(inc.priority, inc.id === selectedId)}
            >
              <Popup>
                <div className="map-popup">
                  <strong>{label(TRIGGER_LABEL, inc.trigger_type)}</strong>
                  <span className="muted">
                    {label(PRIORITY_LABEL, inc.priority)} · {label(STATUS_LABEL, inc.status)} · {timeAgo(inc.created_at)}
                  </span>
                  <span className="faint">
                    Person <span className="mono">{shortId(inc.user_id)}</span>
                  </span>
                  <div className="row">
                    {onSelectIncident && (
                      <button type="button" className="btn btn-small" onClick={() => onSelectIncident(inc)}>
                        Open
                      </button>
                    )}
                    {/* Quick actions only for the two steps that are safe to take from the map. */}
                    {onLifecycle && inc.status === 'CREATED' && (
                      <button type="button" className="btn btn-small btn-primary" onClick={() => onLifecycle('ACKNOWLEDGED', inc)}>
                        {NEXT_ACTION_LABEL.ACKNOWLEDGED}
                      </button>
                    )}
                    {onLifecycle && inc.status === 'ASSIGNED' && (
                      <button type="button" className="btn btn-small btn-primary" onClick={() => onLifecycle('DISPATCHED', inc)}>
                        {NEXT_ACTION_LABEL.DISPATCHED}
                      </button>
                    )}
                  </div>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>

        <div className="legend" aria-label="Legend">
          <span>
            <i className="dot marker-critical" /> Critical
          </span>
          <span>
            <i className="dot marker-high" /> High
          </span>
          <span>
            <i className="dot marker-check" /> Check
          </span>
          {showCameras && (
            <span>
              <i className="marker-camera" style={{ borderWidth: 0 }} /> Camera
            </span>
          )}
        </div>
      </div>
    </section>
  );
}
