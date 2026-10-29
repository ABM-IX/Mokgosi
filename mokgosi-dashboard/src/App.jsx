import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import 'leaflet/dist/leaflet.css';
import { supabase } from './lib/supabaseClient.js';
import {
  DEMO_MODE,
  DEFAULT_DEMO_TOKEN,
  patchIncidentLifecycle,
  postAcousticSimulation,
  postCctvSnapshot,
  postIncidentAudit,
  fetchIncidentReferrals,
  postIncidentReferral,
  fetchSurvivorConsents,
  fetchCameras,
} from './lib/api.js';
import { AUDIT_LABEL, actorLabel, clockTime, humanize, label } from './lib/labels.js';
import { useTheme } from './lib/theme.js';
import { camerasNear } from './lib/geo.js';
import Icon from './components/Icons.jsx';
import AlertBanner from './components/AlertBanner.jsx';
import HeaderBar from './components/HeaderBar.jsx';
import IncidentQueue, { isGbvIncident, sortIncidentsByUrgency } from './components/IncidentQueue.jsx';
import IncidentSummary from './components/IncidentSummary.jsx';
import LiveOperationsMap from './components/LiveOperationsMap.jsx';
import CctvStreamModal from './components/CctvStreamModal.jsx';
import EvidenceDocketModal from './components/EvidenceDocketModal.jsx';
import GbvCaseView from './components/GbvCaseView.jsx';
import HotspotsView from './components/HotspotsView.jsx';
import LandingPortal from './components/LandingPortal.jsx';
import { DEMO_INCIDENTS, DEMO_CAMERAS, DEMO_BREADCRUMBS, DEMO_LOGS } from './lib/demoData.js';

// Marks a demo-mode session. It is not a credential: the API rejects it unless VITE_DEMO_RESPONDER_TOKEN
// is set to the backend's DEMO_RESPONDER_TOKEN.
const DEMO_SESSION = 'demo-session';

function playCriticalAlertTone() {
  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(880, ctx.currentTime);
    osc.frequency.setValueAtTime(660, ctx.currentTime + 0.14);
    gain.gain.setValueAtTime(0.14, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.36);
  } catch {
    // Browser audio gesture policy or headless browser environment.
  }
}

const AUDIO_STATUS = {
  ANALYZED: 'Analysed',
  UNAVAILABLE: 'Not available',
  AWAITING_OR_BYPASSED: 'No audio shared with this alert',
};

function AudioContextCard({ incident, canAct, onSimulate }) {
  const context = incident.ai_context || {};
  const hasAudio = context.status && context.status !== 'AWAITING_OR_BYPASSED';
  if (!hasAudio && !DEMO_MODE) return null;
  return (
    <section className="card" aria-label="Audio context">
      <div className="card-head">
        <h2>Audio context</h2>
        {context.model === 'DETERMINISTIC_DEMO' && <span className="card-note">Demo profile, not a real analysis</span>}
      </div>
      <p className="muted">
        {AUDIO_STATUS[context.status] || humanize(context.status) || AUDIO_STATUS.AWAITING_OR_BYPASSED}
        {context.reason ? `. ${context.reason}` : ''}
      </p>
      {(context.tags || []).length > 0 && (
        <div className="row">
          {context.tags.map((tag) => (
            <span key={tag} className="tag">
              {tag}
            </span>
          ))}
        </div>
      )}
      {DEMO_MODE && (
        <div className="row">
          <span className="faint">Try a demo profile:</span>
          <button type="button" className="btn btn-small" disabled={!canAct} onClick={() => onSimulate('DISTRESSED')}>
            Distress
          </button>
          <button type="button" className="btn btn-small" disabled={!canAct} onClick={() => onSimulate('SILENT')}>
            Silence
          </button>
          <button type="button" className="btn btn-small" disabled={!canAct} onClick={() => onSimulate('CONVERSATION')}>
            Conversation
          </button>
        </div>
      )}
      <p className="card-note">Audio context can raise an alert’s priority. It never lowers, delays or cancels one.</p>
    </section>
  );
}

function RecentActivity({ logs, onOpen }) {
  const recent = logs.slice(-5).reverse();
  return (
    <section className="card" aria-label="Recent activity">
      <div className="card-head">
        <h2>Recent activity</h2>
        <button type="button" className="btn btn-small btn-quiet" onClick={onOpen}>
          Full log
        </button>
      </div>
      {recent.length === 0 ? (
        <p className="muted">Nothing recorded yet.</p>
      ) : (
        <ul className="list-plain">
          {recent.map((log) => (
            <li key={log.id}>
              <span>{label(AUDIT_LABEL, log.action)}</span>
              <span className="faint num">
                {actorLabel(log.actor_id)} · {clockTime(log.timestamp_utc)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function NearbyCameras({ cameras, onOpen }) {
  return (
    <section className="card" aria-label="Nearby cameras">
      <div className="card-head">
        <h2>Cameras near this incident</h2>
        <span className="card-note">Opt-in, within 150 m</span>
      </div>
      {cameras.length === 0 ? (
        <p className="muted">No opt-in cameras are online within 150 m of this incident.</p>
      ) : (
        <ul className="camera-list">
          {cameras.map((cam) => (
            <li key={cam.id}>
              <span className="camera-name">
                <Icon name="camera" size={16} />
                <span>
                  {cam.owner_name}
                  <span className="faint"> · {Math.round(cam.distance_m)} m away</span>
                </span>
              </span>
              <button type="button" className="btn btn-small" onClick={() => onOpen(cam)}>
                View
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default function App() {
  const [incidents, setIncidents] = useState([]);
  const [selected, setSelected] = useState(null);
  const [activeTab, setActiveTab] = useState('ACTIVE');
  const [activePillar, setActivePillar] = useState('SAFER_COMMUNITIES');
  const [saferSubView, setSaferSubView] = useState('MAP'); // 'MAP' | 'HOTSPOTS'
  const { mode: themeMode, resolved: theme, setMode: setThemeMode } = useTheme();

  const [registry, setRegistry] = useState([]);
  const [rpcCameras, setRpcCameras] = useState([]);
  const [locations, setLocations] = useState([]);
  const [logs, setLogs] = useState([]);
  const [manifests, setManifests] = useState([]);
  const [survivorConsents, setSurvivorConsents] = useState(null);
  const [incidentReferralsList, setIncidentReferralsList] = useState([]);
  const [activeCameraModal, setActiveCameraModal] = useState(null);
  const [docketModalOpen, setDocketModalOpen] = useState(false);

  // Responder auth state (Supabase Auth session, or an explicit demo-mode session)
  const [sessionToken, setSessionToken] = useState(DEFAULT_DEMO_TOKEN);
  const [operatorId, setOperatorId] = useState('');

  const [audioEnabled, setAudioEnabled] = useState(false);
  const [lastRealtimeLatencyMs, setLastRealtimeLatencyMs] = useState(null);
  const [error, setError] = useState('');
  const [nowMs, setNowMs] = useState(() => Date.now());
  const audioArmedRef = useRef(false);

  useEffect(() => {
    audioArmedRef.current = audioEnabled;
  }, [audioEnabled]);

  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 15000);
    return () => clearInterval(timer);
  }, []);

  // 1. Supabase Auth session
  useEffect(() => {
    if (!supabase) return undefined;
    supabase.auth.getSession().then(({ data }) => {
      const sess = data?.session;
      if (sess?.access_token) {
        setSessionToken(sess.access_token);
        setOperatorId(sess.user?.email || sess.user?.id || 'Responder');
      }
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, sess) => {
      if (sess?.access_token) {
        setSessionToken(sess.access_token);
        setOperatorId(sess.user?.email || sess.user?.id || 'Responder');
      } else if (!DEMO_MODE) {
        setSessionToken('');
        setOperatorId('');
      }
    });
    return () => sub?.subscription?.unsubscribe();
  }, []);

  // Every consented, online camera, for the city map. The server only returns these to signed-in responders.
  useEffect(() => {
    if (!operatorId) return undefined;
    let live = true;
    fetchCameras(sessionToken).then((list) => live && setRegistry(list));
    return () => {
      live = false;
    };
  }, [operatorId, sessionToken]);

  // 2. Incident list
  const refreshIncidents = useCallback(async () => {
    if (!supabase) {
      if (DEMO_MODE) {
        setIncidents(DEMO_INCIDENTS);
        setSelected((curr) => {
          if (curr) {
            const updated = DEMO_INCIDENTS.find((x) => x.id === curr.id);
            if (updated) return updated;
          }
          const open = DEMO_INCIDENTS.filter((x) => x.status !== 'RESOLVED' && !isGbvIncident(x));
          return sortIncidentsByUrgency(open)[0] || DEMO_INCIDENTS[0] || null;
        });
        return;
      }
      setError('This console is not connected to the database. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.');
      return;
    }
    const { data, error: fetchErr } = await supabase
      .from('incidents')
      .select('*')
      .order('created_at', { ascending: false });
    if (fetchErr) {
      setError(fetchErr.message);
      return;
    }
    const rows = data || [];
    setIncidents(rows);
    setSelected((curr) => {
      if (curr) {
        const updated = rows.find((x) => x.id === curr.id);
        if (updated) return updated;
      }
      const sorted = sortIncidentsByUrgency(rows.filter((x) => x.status !== 'RESOLVED'));
      return sorted[0] || rows[0] || null;
    });
  }, []);

  // 3. Realtime subscription for `incidents`
  useEffect(() => {
    refreshIncidents();
    if (!supabase) return undefined;
    const channel = supabase
      .channel('mokgosi-incidents-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'incidents' }, (payload) => {
        const receivedMs = Date.now();
        if (payload.eventType === 'INSERT' && payload.new) {
          const createdMs = new Date(payload.new.created_at || receivedMs).getTime();
          setLastRealtimeLatencyMs(Math.max(0, receivedMs - createdMs));
          setIncidents((prev) => [payload.new, ...prev.filter((item) => item.id !== payload.new.id)]);
          // A critical GBV alert switches the console to the GBV list.
          if (isGbvIncident(payload.new) && payload.new.priority === 'P1_CRITICAL') {
            setActivePillar('GBV_RESPONSE');
          }
          if (payload.new.priority === 'P1_CRITICAL') {
            setSelected(payload.new);
            setActiveTab('ACTIVE');
            if (audioArmedRef.current) playCriticalAlertTone();
          } else {
            setSelected((curr) => curr || payload.new);
          }
        } else if (payload.eventType === 'UPDATE' && payload.new) {
          setIncidents((prev) => prev.map((item) => (item.id === payload.new.id ? payload.new : item)));
          setSelected((curr) => (curr?.id === payload.new.id ? payload.new : curr));
          if (payload.new.priority === 'P1_CRITICAL' && audioArmedRef.current) playCriticalAlertTone();
        }
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [refreshIncidents]);

  // 4. Details for the selected incident
  useEffect(() => {
    if (!selected) return undefined;
    let mounted = true;

    if (sessionToken) postIncidentAudit(selected.id, 'VIEW_INCIDENT', sessionToken);
    fetchSurvivorConsents(selected.user_id, sessionToken).then((c) => mounted && setSurvivorConsents(c));
    fetchIncidentReferrals(selected.id, sessionToken).then((res) => mounted && setIncidentReferralsList(res?.referrals || []));

    if (!supabase) {
      if (DEMO_MODE) {
        setLocations(DEMO_BREADCRUMBS[selected.id] || []);
        setLogs(DEMO_LOGS[selected.id] || []);
        setManifests([]);
      }
      return () => {
        mounted = false;
      };
    }

    (async () => {
      const [camRes, locRes, logRes, manRes] = await Promise.all([
        supabase.rpc('get_authorized_nearby_cameras', { inc_lat: selected.lat, inc_lng: selected.lng, radius_m: 150 }),
        supabase.from('incident_locations').select('*').eq('incident_id', selected.id).order('captured_at_utc', { ascending: true }),
        supabase.from('evidence_audit_logs').select('*').eq('incident_id', selected.id).order('timestamp_utc', { ascending: true }),
        supabase.from('evidence_manifests').select('*').eq('incident_id', selected.id).order('server_receipt_utc', { ascending: true }),
      ]);
      if (!mounted) return;
      setRpcCameras(camRes.data || []);
      setLocations(locRes.data || []);
      setLogs(logRes.data || []);
      setManifests(manRes.data || []);
    })();

    const detailChannel = supabase
      .channel(`mokgosi-incident-${selected.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'evidence_manifests', filter: `incident_id=eq.${selected.id}` }, (payload) => {
        if (payload.new) setManifests((prev) => (prev.some((m) => m.id === payload.new.id) ? prev : [...prev, payload.new]));
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'evidence_audit_logs', filter: `incident_id=eq.${selected.id}` }, (payload) => {
        if (payload.new) setLogs((prev) => (prev.some((l) => l.id === payload.new.id) ? prev : [...prev, payload.new]));
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'incident_locations', filter: `incident_id=eq.${selected.id}` }, (payload) => {
        if (payload.new) setLocations((prev) => [...prev, payload.new]);
      })
      .subscribe();

    return () => {
      mounted = false;
      supabase.removeChannel(detailChannel);
    };
  }, [selected?.id, selected?.lat, selected?.lng, selected?.user_id, sessionToken]);

  // 5. Shift numbers for the top bar
  const { openP1Count, medianAckSeconds, saferActiveCount, gbvActiveCount } = useMemo(() => {
    const active = incidents.filter((i) => i.status !== 'RESOLVED');
    const ackDurations = incidents
      .filter((i) => i.created_at && i.acknowledged_at)
      .map((i) => Math.max(0, Math.round((new Date(i.acknowledged_at) - new Date(i.created_at)) / 1000)))
      .sort((a, b) => a - b);
    let median = null;
    if (ackDurations.length > 0) {
      const mid = Math.floor(ackDurations.length / 2);
      median = ackDurations.length % 2 ? ackDurations[mid] : Math.round((ackDurations[mid - 1] + ackDurations[mid]) / 2);
    }
    return {
      openP1Count: active.filter((i) => i.priority === 'P1_CRITICAL').length,
      medianAckSeconds: median,
      saferActiveCount: active.filter((i) => !isGbvIncident(i)).length,
      gbvActiveCount: active.filter((i) => isGbvIncident(i)).length,
    };
  }, [incidents]);

  function handlePillarChange(nextPillar) {
    setActivePillar(nextPillar);
    const inPillar = (i) => (nextPillar === 'GBV_RESPONSE' ? isGbvIncident(i) : !isGbvIncident(i));
    const sorted = sortIncidentsByUrgency(incidents.filter((i) => i.status !== 'RESOLVED' && inPillar(i)));
    setSelected(sorted[0] || incidents.find(inPillar) || null);
  }

  async function handleResponderSignIn(email, password) {
    setError('');
    if (DEMO_MODE && (!supabase || !password)) {
      setSessionToken(DEFAULT_DEMO_TOKEN || DEMO_SESSION);
      setOperatorId(email || 'Demo responder');
      return;
    }
    if (!supabase) {
      throw new Error('Sign-in is unavailable: this console is not connected to Supabase.');
    }
    const { data, error: signErr } = await supabase.auth.signInWithPassword({ email, password });
    if (signErr) throw signErr;
    if (data?.session) {
      setSessionToken(data.session.access_token);
      setOperatorId(data.user?.email || data.user?.id || 'Responder');
    }
  }

  async function handleSignOut() {
    if (supabase) await supabase.auth.signOut();
    setSessionToken('');
    setOperatorId('');
  }

  async function handleLifecycle(nextStatus, targetIncident = null) {
    const target = targetIncident || selected;
    if (!target) return;
    setError('');
    try {
      const res = await patchIncidentLifecycle(target.id, nextStatus, sessionToken);
      if (res?.incident) {
        setIncidents((prev) => prev.map((i) => (i.id === res.incident.id ? res.incident : i)));
        if (selected?.id === target.id) setSelected(res.incident);
        if (res.incident.status === 'RESOLVED' && selected?.id === target.id) setActiveTab('RESOLVED');
        return;
      }
    } catch (err) {
      if (DEMO_MODE) {
        // Sample data: apply the change locally so the walkthrough still works without a backend.
        const stamp = new Date().toISOString();
        const updated = {
          ...target,
          status: nextStatus,
          acknowledged_by: nextStatus === 'ACKNOWLEDGED' ? operatorId : target.acknowledged_by,
          acknowledged_at: nextStatus === 'ACKNOWLEDGED' ? stamp : target.acknowledged_at,
          assigned_to: nextStatus === 'ASSIGNED' ? operatorId : target.assigned_to,
          assigned_at: nextStatus === 'ASSIGNED' ? stamp : target.assigned_at,
          dispatched_at: nextStatus === 'DISPATCHED' ? stamp : target.dispatched_at,
          resolved_at: nextStatus === 'RESOLVED' ? stamp : target.resolved_at,
        };
        setIncidents((prev) => prev.map((i) => (i.id === target.id ? updated : i)));
        if (selected?.id === target.id) {
          setSelected(updated);
          if (nextStatus === 'RESOLVED') setActiveTab('RESOLVED');
        }
        return;
      }
      setError(err.message);
    }
  }

  async function handleAcousticSimulation(profile) {
    if (!selected) return;
    setError('');
    try {
      const res = await postAcousticSimulation(selected.id, profile, sessionToken);
      if (res?.incident) {
        setIncidents((prev) => prev.map((i) => (i.id === res.incident.id ? res.incident : i)));
        setSelected(res.incident);
      } else if (res?.ai_context) {
        setSelected((curr) => (curr ? { ...curr, ai_context: res.ai_context } : curr));
      }
      if (res?.signed_manifest) setManifests((prev) => [...prev, res.signed_manifest]);
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleRecordReferral(partnerId, notes) {
    if (!selected || !sessionToken) return;
    try {
      const res = await postIncidentReferral(selected.id, partnerId, notes, sessionToken);
      if (res?.referral) setIncidentReferralsList((prev) => [res.referral, ...prev]);
    } catch (err) {
      if (DEMO_MODE) {
        const stamp = new Date().toISOString();
        setIncidentReferralsList((prev) => [
          { id: `demo-${stamp}`, partner_id: partnerId, notes, referred_by: operatorId, referred_at: stamp },
          ...prev,
        ]);
        return;
      }
      setError(err.message);
      throw err;
    }
  }

  function handleOpenCameraModal(camera) {
    setActiveCameraModal(camera);
    if (selected && sessionToken) postIncidentAudit(selected.id, 'OPEN_CCTV_STREAM', sessionToken);
  }

  async function handleCaptureSnapshot(cameraId) {
    if (!selected) return null;
    const res = await postCctvSnapshot(selected.id, cameraId, sessionToken);
    if (res?.manifest) setManifests((prev) => [...prev, res.manifest]);
    return res;
  }

  function handleOpenDocketModal() {
    setDocketModalOpen(true);
    if (selected && sessionToken) postIncidentAudit(selected.id, 'VIEW_EVIDENCE', sessionToken);
  }

  const handleSelectIncident = useCallback((inc) => {
    if (!inc) return;
    setSelected(inc);
    if (isGbvIncident(inc)) {
      setActivePillar('GBV_RESPONSE');
    } else {
      setActivePillar('SAFER_COMMUNITIES');
      setSaferSubView('MAP');
    }
  }, []);

  // The map shows the whole registry; the incident panel shows only what is within 150 m of the selection.
  const registryAll = useMemo(() => {
    const byId = new Map();
    const base = DEMO_MODE && registry.length === 0 && rpcCameras.length === 0 ? DEMO_CAMERAS : [];
    [...base, ...registry, ...rpcCameras].forEach((cam) => byId.set(cam.id, cam));
    return [...byId.values()];
  }, [registry, rpcCameras]);
  const nearCameras = useMemo(
    () => (selected ? camerasNear(registryAll, Number(selected.lat), Number(selected.lng), 150) : []),
    [registryAll, selected],
  );

  const unackedCritical = incidents.filter((i) => i.priority === 'P1_CRITICAL' && i.status === 'CREATED').length;
  useEffect(() => {
    document.title = unackedCritical > 0 ? `(${unackedCritical}) Critical alert · Mokgosi` : 'Mokgosi · Responder console';
  }, [unackedCritical]);

  if (!operatorId) {
    return <LandingPortal onSignIn={handleResponderSignIn} error={error} demoMode={DEMO_MODE} />;
  }

  const isPublic = activePillar === 'SAFER_COMMUNITIES';
  const selectedHere = selected && isGbvIncident(selected) !== isPublic ? selected : null;
  const canAct = Boolean(sessionToken);

  const incidentPanel = selectedHere ? (
    <>
      <IncidentSummary
        incident={selectedHere}
        canAct={canAct}
        onLifecycle={(next) => handleLifecycle(next)}
        onOpenEvidence={handleOpenDocketModal}
        nowMs={nowMs}
      />
      {isGbvIncident(selectedHere) ? (
        <GbvCaseView
          incident={selectedHere}
          allIncidents={incidents}
          consents={survivorConsents}
          referrals={incidentReferralsList}
          manifests={manifests}
          logs={logs}
          cameras={nearCameras}
          locations={locations}
          theme={theme}
          onRecordReferral={handleRecordReferral}
          onOpenDocket={handleOpenDocketModal}
          onOpenCameraStream={handleOpenCameraModal}
        />
      ) : (
        <>
          <NearbyCameras cameras={nearCameras} onOpen={handleOpenCameraModal} />
          <AudioContextCard incident={selectedHere} canAct={canAct} onSimulate={handleAcousticSimulation} />
          <RecentActivity logs={logs} onOpen={handleOpenDocketModal} />
        </>
      )}
    </>
  ) : (
    <div className="empty-state">
      <Icon name={isPublic ? 'map' : 'shield'} size={28} />
      <strong>{isPublic ? 'Nothing selected' : 'No GBV incident selected'}</strong>
      <span>
        {isPublic
          ? 'Choose an incident from the list, or select one on the map.'
          : 'New alerts appear in the list as they arrive. Choose one to see the case.'}
      </span>
    </div>
  );

  return (
    <div className="console">
      <HeaderBar
        meshOnline={Boolean(supabase)}
        demoMode={DEMO_MODE}
        operatorId={operatorId}
        openP1Count={openP1Count}
        medianAckSeconds={medianAckSeconds}
        lastRealtimeLatencyMs={lastRealtimeLatencyMs}
        audioEnabled={audioEnabled}
        onToggleAudio={() => {
          const next = !audioEnabled;
          setAudioEnabled(next);
          if (next) playCriticalAlertTone();
        }}
        onSignOut={handleSignOut}
        activePillar={activePillar}
        onPillarChange={handlePillarChange}
        saferCount={saferActiveCount}
        gbvCount={gbvActiveCount}
        themeMode={themeMode}
        onThemeChange={setThemeMode}
      />

      {DEMO_MODE && (
        <div className="notice-strip">Demo mode. Everything here is sample data, and nothing you do reaches a real person.</div>
      )}
      {error && (
        <div className="notice-strip is-error" role="alert">
          <span>{error}</span>
          <button type="button" className="btn btn-small" onClick={() => setError('')}>
            Dismiss
          </button>
        </div>
      )}
      <AlertBanner incidents={incidents} onOpen={handleSelectIncident} nowMs={nowMs} />

      <div className={`workspace ${isPublic ? 'is-public' : 'is-gbv'}`}>
        <IncidentQueue
          incidents={incidents}
          selectedId={selected?.id}
          onSelect={handleSelectIncident}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          activePillar={activePillar}
        />

        {isPublic ? (
          <>
            <section className="stage" aria-label="Map and trends">
              <div className="stage-head">
                <div className="tabs view-tabs" role="tablist" aria-label="View">
                  <button type="button" role="tab" aria-selected={saferSubView === 'MAP'} onClick={() => setSaferSubView('MAP')}>
                    <Icon name="map" size={15} /> City map
                  </button>
                  <button type="button" role="tab" aria-selected={saferSubView === 'HOTSPOTS'} onClick={() => setSaferSubView('HOTSPOTS')}>
                    <Icon name="chart" size={15} /> Area trends
                  </button>
                </div>
              </div>
              {saferSubView === 'HOTSPOTS' ? (
                <div className="stage-scroll">
                  <HotspotsView />
                </div>
              ) : (
                <LiveOperationsMap
                  incidents={incidents}
                  selectedId={selected?.id}
                  onSelectIncident={handleSelectIncident}
                  onLifecycle={handleLifecycle}
                  cameras={registryAll}
                  onOpenCameraStream={handleOpenCameraModal}
                  activePillar={activePillar}
                  theme={theme}
                />
              )}
            </section>
            <aside className="detail-panel" aria-label="Incident details">
              <div className="detail-inner">{incidentPanel}</div>
            </aside>
          </>
        ) : (
          <section className="detail" aria-label="Incident details">
            <div className="detail-inner">{incidentPanel}</div>
          </section>
        )}
      </div>

      {activeCameraModal && selected && (
        <CctvStreamModal camera={activeCameraModal} onClose={() => setActiveCameraModal(null)} onCaptureSnapshot={handleCaptureSnapshot} />
      )}
      {docketModalOpen && selected && (
        <EvidenceDocketModal manifests={manifests} logs={logs} isModal onClose={() => setDocketModalOpen(false)} />
      )}
    </div>
  );
}
