import React, { useEffect, useMemo, useState } from 'react';
import { Circle, MapContainer, Marker, Polygon, Polyline, Popup, TileLayer, useMap } from 'react-leaflet';
import Icon from './Icons.jsx';
import { isGbvIncident } from './IncidentQueue.jsx';
import { camerasNear, isUsableCamera } from '../lib/geo.js';
import { NEXT_ACTION_LABEL, PRIORITY_LABEL, STATUS_LABEL, TRIGGER_LABEL, label, shortId, timeAgo } from '../lib/labels.js';
import { ACCENT, PRIORITY_COLOR, cameraIcon, computeCameraFovCone, coneStyle, incidentIcon, tileFor } from '../lib/mapStyle.js';

export const GABORONE_CBD = [-24.6545, 25.9085];
const PRIORITY_FILTERS = [
  ['ALL', 'All'],
  ['P1_CRITICAL', 'Critical'],
  ['P2_HIGH', 'High'],
  ['P3_VERIFY', 'Check'],
];
const Z_BY_PRIORITY = { P1_CRITICAL: 1000, P2_HIGH: 600, P3_VERIFY: 300 };

/** Moves the map when the selection changes or the recenter button is pressed. */
function MapFlyTo({ target }) {
  const map = useMap();
  useEffect(() => {
    if (!target) return;
    if (target.bounds) map.flyToBounds(target.bounds, { padding: [70, 70], maxZoom: 15, duration: 0.7 });
    else map.flyTo(target.center, target.zoom, { duration: 0.7 });
    // `key` changes on every request, so the same target can be requested twice.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target?.key, map]);
  return null;
}

/**
 * The console's main view: every open incident and every registered, consented camera on one map.
 * The selected incident gets a 150 m circle, the cameras inside it light up, and the rest stay quiet.
 */
export default function LiveOperationsMap({
  incidents = [],
  selectedId = null,
  onSelectIncident,
  onLifecycle,
  cameras = [],
  onOpenCameraStream,
  activePillar = 'ALL',
  theme = 'light',
}) {
  const [priorityFilter, setPriorityFilter] = useState('ALL');
  const [showCameras, setShowCameras] = useState(true);
  const [showRadii, setShowRadii] = useState(true);
  const [recenterTick, setRecenterTick] = useState(0);

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

  const registry = useMemo(() => cameras.filter(isUsableCamera), [cameras]);
  const selected = shown.find((inc) => inc.id === selectedId) || incidents.find((inc) => inc.id === selectedId) || null;
  const nearCameras = useMemo(
    () => (selected ? camerasNear(registry, Number(selected.lat), Number(selected.lng), 150) : []),
    [registry, selected],
  );
  const nearIds = new Set(nearCameras.map((cam) => cam.id));

  // Where the map should be looking. A selection wins; Recenter falls back to everything that is open.
  const target = useMemo(() => {
    if (recenterTick > 0 && !selected) {
      const points = shown.map((inc) => [Number(inc.lat), Number(inc.lng)]);
      if (points.length > 1) return { key: `fit-${recenterTick}`, bounds: points };
      if (points.length === 1) return { key: `fit-${recenterTick}`, center: points[0], zoom: 15 };
      return { key: `fit-${recenterTick}`, center: GABORONE_CBD, zoom: 13 };
    }
    if (selected?.lat != null) return { key: `sel-${selected.id}-${recenterTick}`, center: [Number(selected.lat), Number(selected.lng)], zoom: 16 };
    return null;
  }, [selected?.id, selected?.lat, selected?.lng, recenterTick, shown.length]); // eslint-disable-line react-hooks/exhaustive-deps

  const tiles = tileFor(theme);

  return (
    <section className="map-stage" aria-label="City map">
      <MapContainer center={GABORONE_CBD} zoom={13} zoomControl={false} scrollWheelZoom className="map-canvas">
        <MapFlyTo target={target} />
        <TileLayer key={theme} url={tiles.url} attribution={tiles.attribution} subdomains={tiles.subdomains} />

        {showRadii &&
          shown.map((inc) => (
            <Circle
              key={`radius-${inc.id}`}
              center={[Number(inc.lat), Number(inc.lng)]}
              radius={150}
              pathOptions={{
                color: PRIORITY_COLOR[inc.priority] || PRIORITY_COLOR.P3_VERIFY,
                weight: inc.id === selectedId ? 1.6 : 1,
                fillOpacity: inc.id === selectedId ? 0.08 : 0.03,
                dashArray: inc.id === selectedId ? undefined : '4 5',
                interactive: false,
              }}
            />
          ))}

        {showCameras &&
          registry.map((cam) => {
            const near = nearIds.has(cam.id);
            return (
              <React.Fragment key={`cam-${cam.id}`}>
                <Polygon
                  positions={computeCameraFovCone(Number(cam.lat), Number(cam.lng), Number(cam.azimuth_deg ?? 180), Number(cam.fov_deg ?? 90), near ? 95 : 70)}
                  pathOptions={coneStyle(near)}
                />
                <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={cameraIcon(near)} zIndexOffset={near ? 700 : 100}>
                  <Popup>
                    <div className="map-popup">
                      <strong>{cam.owner_name}</strong>
                      <span className="muted">
                        {near ? `${Math.round(nearCameras.find((c) => c.id === cam.id)?.distance_m || 0)} m from the selected incident` : 'Opt-in camera'}
                      </span>
                      {onOpenCameraStream && (
                        <button type="button" className="btn btn-small" onClick={() => onOpenCameraStream(cam)}>
                          <Icon name="camera" size={14} /> View camera
                        </button>
                      )}
                    </div>
                  </Popup>
                </Marker>
              </React.Fragment>
            );
          })}

        {showCameras &&
          selected &&
          nearCameras.map((cam) => (
            <Polyline
              key={`link-${cam.id}`}
              positions={[
                [Number(selected.lat), Number(selected.lng)],
                [Number(cam.lat), Number(cam.lng)],
              ]}
              pathOptions={{ color: ACCENT, weight: 1.2, dashArray: '3 5', opacity: 0.8, interactive: false }}
            />
          ))}

        {shown.map((inc) => (
          <Marker
            key={`inc-${inc.id}`}
            position={[Number(inc.lat), Number(inc.lng)]}
            icon={incidentIcon(inc, inc.id === selectedId)}
            zIndexOffset={(Z_BY_PRIORITY[inc.priority] || 0) + (inc.id === selectedId ? 2000 : 0)}
            eventHandlers={{ click: () => onSelectIncident?.(inc) }}
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

      <div className="map-overlay map-overlay-tl" role="toolbar" aria-label="Priority filter">
        {PRIORITY_FILTERS.map(([key, text]) => (
          <button key={key} type="button" className="chip" aria-pressed={priorityFilter === key} onClick={() => setPriorityFilter(key)}>
            {text}
            <span className="chip-count">{countFor(key)}</span>
          </button>
        ))}
      </div>

      <div className="map-overlay map-overlay-tr" role="toolbar" aria-label="Map layers">
        <label className="switch">
          <input type="checkbox" checked={showCameras} onChange={(e) => setShowCameras(e.target.checked)} />
          <span>Cameras ({registry.length})</span>
        </label>
        <label className="switch">
          <input type="checkbox" checked={showRadii} onChange={(e) => setShowRadii(e.target.checked)} />
          <span>150 m circles</span>
        </label>
        <button type="button" className="btn btn-small btn-quiet" onClick={() => setRecenterTick((n) => n + 1)}>
          <Icon name="crosshair" size={14} /> Recenter
        </button>
      </div>

      <div className="map-overlay map-overlay-bl legend" aria-label="Legend">
        <span>
          <svg viewBox="0 0 32 32" width="16" height="16" aria-hidden="true">
            <circle cx="16" cy="16" r="13" fill={PRIORITY_COLOR.P1_CRITICAL} />
            <path d="M16 9.5v9" stroke="#fff" strokeWidth="3" strokeLinecap="round" />
            <circle cx="16" cy="23" r="1.9" fill="#fff" />
          </svg>
          Critical
        </span>
        <span>
          <svg viewBox="0 0 32 32" width="16" height="16" aria-hidden="true">
            <path d="M16 4.2 28.6 26.2H3.4Z" fill={PRIORITY_COLOR.P2_HIGH} stroke={PRIORITY_COLOR.P2_HIGH} strokeWidth="3" strokeLinejoin="round" />
            <path d="M16 12.5v6.2" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" />
            <circle cx="16" cy="22.4" r="1.6" fill="#fff" />
          </svg>
          High
        </span>
        <span>
          <svg viewBox="0 0 32 32" width="16" height="16" aria-hidden="true">
            <circle cx="16" cy="16" r="12" fill={PRIORITY_COLOR.P3_VERIFY} />
            <path d="M10.6 16.4l3.8 3.8 7-7.6" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Check
        </span>
        <span>
          <i className="legend-badge" aria-hidden="true" />
          Silent alert: do not contact
        </span>
        {showCameras && (
          <span>
            <i className="legend-cam" aria-hidden="true" />
            Camera
          </span>
        )}
      </div>

      {open.length === 0 && (
        <div className="map-empty" role="status">
          <strong>All quiet</strong>
          <span>No open incidents. New alerts appear on the map the moment they arrive.</span>
        </div>
      )}
    </section>
  );
}
