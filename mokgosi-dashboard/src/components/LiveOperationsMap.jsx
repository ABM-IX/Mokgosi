import React, { useState, useMemo } from 'react';
import L from 'leaflet';
import {
  MapContainer,
  TileLayer,
  Marker,
  Popup,
  Circle,
  Polygon,
  useMap,
} from 'react-leaflet';
import { isGbvIncident } from './IncidentQueue.jsx';
import { computeCameraFovCone } from './TacticalMap.jsx';

function createLiveIncidentIcon(priority, isSelected = false) {
  const color =
    priority === 'P1_CRITICAL'
      ? '#e11d48'
      : priority === 'P2_HIGH'
      ? '#f59e0b'
      : '#0ea5e9';

  const pulseClass = priority === 'P1_CRITICAL' ? 'mokgosi-pulse-marker' : '';
  const selectedHalo = isSelected
    ? 'border: 3px solid #35c898; box-shadow: 0 0 0 5px rgba(53, 200, 152, 0.45);'
    : `border: 2px solid #ffffff; box-shadow: 0 0 0 4px ${color}55;`;

  return L.divIcon({
    className: `mokgosi-live-incident-icon ${pulseClass}`,
    html: `<div style="width:20px;height:20px;border-radius:50%;background:${color};${selectedHalo}display:flex;align-items:center;justify-content:center;color:#fff;font-weight:900;font-size:9px;text-shadow:0 1px 2px #000;">${
      priority === 'P1_CRITICAL' ? '!' : priority === 'P2_HIGH' ? '▲' : '●'
    }</div>`,
    iconSize: [22, 22],
    iconAnchor: [11, 11],
  });
}

const CAMERA_ICON = L.divIcon({
  className: 'mokgosi-cam-icon',
  html: `<div style="width:16px;height:16px;border-radius:4px;background:#10b981;border:2px solid #052e16;box-shadow:0 0 6px #10b981cc;display:flex;align-items:center;justify-content:center;color:#052e16;font-size:10px;font-weight:bold;">📷</div>`,
  iconSize: [16, 16],
  iconAnchor: [8, 8],
});

function formatRelativeTime(dateStr) {
  if (!dateStr) return 'Just now';
  const diffSec = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000);
  if (diffSec < 45) return 'Just now';
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  return `${Math.floor(diffSec / 3600)}h ago`;
}

function MapViewController({ center, zoom }) {
  const map = useMap();
  React.useEffect(() => {
    if (center && map) {
      map.setView(center, zoom, { animate: true });
    }
  }, [center, zoom, map]);
  return null;
}

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
  const [statusFilter, setStatusFilter] = useState('ACTIVE');
  const [showCameras, setShowCameras] = useState(true);
  const [showRadii, setShowRadii] = useState(true);
  const [mapCenter, setMapCenter] = useState([-24.656, 25.912]);
  const [mapZoom, setMapZoom] = useState(14);

  const filteredIncidents = useMemo(() => {
    return incidents.filter((inc) => {
      if (!inc.lat || !inc.lng) return false;
      // Pillar filter (if component invoked with activePillar context)
      if (activePillar === 'SAFER_COMMUNITIES' && isGbvIncident(inc)) return false;
      if (activePillar === 'GBV_RESPONSE' && !isGbvIncident(inc)) return false;

      // Status filter
      if (statusFilter === 'ACTIVE' && inc.status === 'RESOLVED') return false;
      if (statusFilter === 'UNACKNOWLEDGED' && inc.status !== 'CREATED') return false;
      if (statusFilter === 'RESOLVED' && inc.status !== 'RESOLVED') return false;

      // Priority filter
      if (priorityFilter !== 'ALL' && inc.priority !== priorityFilter) return false;

      return true;
    });
  }, [incidents, activePillar, statusFilter, priorityFilter]);

  const p1Count = incidents.filter((i) => i.priority === 'P1_CRITICAL' && i.status !== 'RESOLVED').length;
  const p2Count = incidents.filter((i) => i.priority === 'P2_HIGH' && i.status !== 'RESOLVED').length;
  const p3Count = incidents.filter((i) => i.priority === 'P3_VERIFY' && i.status !== 'RESOLVED').length;

  function handleCenterGaborone() {
    setMapCenter([-24.655, 25.912]);
    setMapZoom(14);
  }

  return (
    <div className="panel live-map-panel" aria-label="Citywide Operations & Tactical Map">
      <div className="live-map-header">
        <div>
          <h3>Citywide Live Operations &amp; Dispatch Map</h3>
          <small>
            Real-time multi-incident mesh · Gaborone &amp; Regional jurisdiction · {filteredIncidents.length} shown
          </small>
        </div>

        {/* Filter Toolbar */}
        <div className="live-map-controls" role="toolbar" aria-label="Map Display Controls">
          <div className="map-filter-group" aria-label="Priority Filter">
            <span className="control-label">Priority:</span>
            <button
              type="button"
              className={`filter-chip ${priorityFilter === 'ALL' ? 'active' : ''}`}
              onClick={() => setPriorityFilter('ALL')}
            >
              All ({incidents.filter((i) => i.status !== 'RESOLVED').length})
            </button>
            <button
              type="button"
              className={`filter-chip p1-chip ${priorityFilter === 'P1_CRITICAL' ? 'active' : ''}`}
              onClick={() => setPriorityFilter('P1_CRITICAL')}
            >
              P1 Critical ({p1Count})
            </button>
            <button
              type="button"
              className={`filter-chip p2-chip ${priorityFilter === 'P2_HIGH' ? 'active' : ''}`}
              onClick={() => setPriorityFilter('P2_HIGH')}
            >
              P2 ({p2Count})
            </button>
            <button
              type="button"
              className={`filter-chip p3-chip ${priorityFilter === 'P3_VERIFY' ? 'active' : ''}`}
              onClick={() => setPriorityFilter('P3_VERIFY')}
            >
              P3 ({p3Count})
            </button>
          </div>

          <div className="map-filter-group" aria-label="Overlay Toggles">
            <label className="toggle-label">
              <input
                type="checkbox"
                checked={showCameras}
                onChange={(e) => setShowCameras(e.target.checked)}
              />
              CCTV Mesh ({cameras.length})
            </label>
            <label className="toggle-label">
              <input
                type="checkbox"
                checked={showRadii}
                onChange={(e) => setShowRadii(e.target.checked)}
              />
              150m Radii
            </label>
            <button
              type="button"
              className="btn-recenter"
              onClick={handleCenterGaborone}
              title="Reset view to Gaborone CBD"
            >
              Center CBD
            </button>
          </div>
        </div>
      </div>

      <div className="map live-operations-canvas">
        <MapContainer
          center={mapCenter}
          zoom={mapZoom}
          scrollWheelZoom={true}
          style={{ height: '100%', width: '100%' }}
        >
          <MapViewController center={mapCenter} zoom={mapZoom} />

          <TileLayer
            attribution="&copy; OpenStreetMap contributors &amp; Mokgosi Tactical Engine"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />

          {/* 150m PostGIS Safety Radii for Active Incidents */}
          {showRadii &&
            filteredIncidents.map((inc) => (
              <Circle
                key={`radius-${inc.id}`}
                center={[Number(inc.lat), Number(inc.lng)]}
                radius={150}
                pathOptions={{
                  color:
                    inc.priority === 'P1_CRITICAL'
                      ? '#e11d48'
                      : inc.priority === 'P2_HIGH'
                      ? '#f59e0b'
                      : '#0ea5e9',
                  weight: 1.2,
                  fillOpacity: 0.08,
                  dashArray: inc.id === selectedId ? undefined : '4 4',
                }}
              />
            ))}

          {/* Public Safety CCTV Mesh Cameras & Directional FOV Cones */}
          {showCameras &&
            cameras.map((cam) => {
              const cone = computeCameraFovCone(
                Number(cam.lat),
                Number(cam.lng),
                Number(cam.azimuth_deg ?? 180),
                Number(cam.fov_deg ?? 90),
                90,
              );
              return (
                <React.Fragment key={`cam-${cam.id}`}>
                  <Polygon
                    positions={cone}
                    pathOptions={{
                      color: '#10b981',
                      weight: 1,
                      fillColor: '#10b981',
                      fillOpacity: 0.18,
                    }}
                  />
                  <Marker position={[Number(cam.lat), Number(cam.lng)]} icon={CAMERA_ICON}>
                    <Popup className="mokgosi-popup">
                      <div className="popup-inner">
                        <div className="popup-badge cam-badge">📷 CCTV Node</div>
                        <strong>{cam.owner_name}</strong>
                        <div className="popup-meta">
                          Azimuth: {cam.azimuth_deg}° · FOV: {cam.fov_deg}°
                        </div>
                        {onOpenCameraStream && (
                          <button
                            type="button"
                            className="popup-action-btn btn-cctv"
                            onClick={() => onOpenCameraStream(cam)}
                          >
                            Open Authorized Stream &amp; Snapshot
                          </button>
                        )}
                      </div>
                    </Popup>
                  </Marker>
                </React.Fragment>
              );
            })}

          {/* Incident Markers */}
          {filteredIncidents.map((inc) => {
            const isSelected = inc.id === selectedId;
            const isGbv = isGbvIncident(inc);
            return (
              <Marker
                key={`inc-${inc.id}`}
                position={[Number(inc.lat), Number(inc.lng)]}
                icon={createLiveIncidentIcon(inc.priority, isSelected)}
              >
                <Popup className="mokgosi-popup">
                  <div className="popup-inner">
                    <div className="popup-header-row">
                      <span className={`popup-priority-badge ${inc.priority.toLowerCase()}`}>
                        {inc.priority.replace('_', ' ')}
                      </span>
                      <span className="popup-status-badge">{inc.status}</span>
                    </div>

                    <div className="popup-title">
                      <strong>Incident #{inc.id.slice(0, 8)}</strong>
                      <div className="popup-trigger">
                        {isGbv && '🛡️ GBV · '}
                        {inc.trigger_type}
                      </div>
                    </div>

                    <div className="popup-meta">
                      <div>User: <b>{inc.user_id}</b></div>
                      <div>Elapsed: <b>{formatRelativeTime(inc.created_at)}</b></div>
                      <div>GPS: {Number(inc.lat).toFixed(5)}, {Number(inc.lng).toFixed(5)}</div>
                      {inc.impact_g_force && inc.impact_g_force > 1.0 && (
                        <div>Impact: <b>{inc.impact_g_force}g</b></div>
                      )}
                    </div>

                    <div className="popup-actions">
                      {onSelectIncident && (
                        <button
                          type="button"
                          className="popup-action-btn btn-primary"
                          onClick={() => onSelectIncident(inc)}
                        >
                          {isSelected ? '✓ Viewing This Case' : 'Open Case Details'}
                        </button>
                      )}

                      {onLifecycle && inc.status === 'CREATED' && (
                        <button
                          type="button"
                          className="popup-action-btn btn-ack"
                          onClick={() => onLifecycle('ACKNOWLEDGED', inc)}
                        >
                          Quick Acknowledge
                        </button>
                      )}

                      {onLifecycle && inc.status === 'ASSIGNED' && (
                        <button
                          type="button"
                          className="popup-action-btn btn-dispatch"
                          onClick={() => onLifecycle('DISPATCHED', inc)}
                        >
                          Quick Dispatch
                        </button>
                      )}
                    </div>
                  </div>
                </Popup>
              </Marker>
            );
          })}
        </MapContainer>

        {/* Map Telemetry HUD */}
        <div className="map-hud-overlay" aria-label="Incident Telemetry HUD">
          <div className="hud-metric">
            <span className="hud-label">Active Mesh</span>
            <span className="hud-val">{filteredIncidents.length} Alerts</span>
          </div>
          <div className="hud-metric hud-critical">
            <span className="hud-label">Critical P1</span>
            <span className="hud-val">{p1Count} Urgent</span>
          </div>
          <div className="hud-metric">
            <span className="hud-label">Cameras</span>
            <span className="hud-val">{cameras.length} Online</span>
          </div>
        </div>

        {/* Floating Map Legend */}
        <div className="map-legend-overlay" aria-label="Tactical Legend">
          <div className="legend-item">
            <span className="legend-dot p1-dot"></span> P1 Critical
          </div>
          <div className="legend-item">
            <span className="legend-dot p2-dot"></span> P2 High
          </div>
          <div className="legend-item">
            <span className="legend-dot p3-dot"></span> P3 Verify
          </div>
          {showCameras && (
            <div className="legend-item">
              <span className="legend-box cam-box"></span> CCTV Node
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
