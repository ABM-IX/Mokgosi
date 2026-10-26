import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import 'leaflet/dist/leaflet.css';
import { supabase } from './lib/supabaseClient.js';
import {
  DEMO_MODE,
  DEFAULT_DEMO_TOKEN,
  RESPONDER_REFERRAL_RESOURCES,
  patchIncidentLifecycle,
  postAcousticSimulation,
  postCctvSnapshot,
  postIncidentAudit,
  fetchIncidentReferrals,
  postIncidentReferral,
  fetchSurvivorConsents,
} from './lib/api.js';
import HeaderBar from './components/HeaderBar.jsx';
import IncidentQueue, { isGbvIncident, sortIncidentsByUrgency } from './components/IncidentQueue.jsx';
import TacticalMap from './components/TacticalMap.jsx';
import LiveOperationsMap from './components/LiveOperationsMap.jsx';
import CctvStreamModal from './components/CctvStreamModal.jsx';
import EvidenceDocketModal from './components/EvidenceDocketModal.jsx';
import GbvCaseView from './components/GbvCaseView.jsx';
import HotspotsView from './components/HotspotsView.jsx';
import { DEMO_INCIDENTS, DEMO_CAMERAS, DEMO_BREADCRUMBS } from './lib/demoData.js';

const NEXT_STATUS = {
  CREATED: 'ACKNOWLEDGED',
  ACKNOWLEDGED: 'ASSIGNED',
  ASSIGNED: 'DISPATCHED',
  DISPATCHED: 'RESOLVED',
};

function playCriticalAlertTone() {
  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sawtooth';
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

export default function App() {
  const [incidents, setIncidents] = useState([]);
  const [selected, setSelected] = useState(null);
  const [activeTab, setActiveTab] = useState('ACTIVE');
  const [activePillar, setActivePillar] = useState('SAFER_COMMUNITIES');
  const [saferSubView, setSaferSubView] = useState('LIVE_MAP'); // 'LIVE_MAP' | 'TACTICAL_MAP' | 'HOTSPOTS'

  const [cameras, setCameras] = useState([]);
  const [locations, setLocations] = useState([]);
  const [logs, setLogs] = useState([]);
  const [manifests, setManifests] = useState([]);
  const [survivorConsents, setSurvivorConsents] = useState(null);
  const [incidentReferralsList, setIncidentReferralsList] = useState([]);
  const [activeCameraModal, setActiveCameraModal] = useState(null);
  const [docketModalOpen, setDocketModalOpen] = useState(false);

  // Responder auth state (Supabase Auth session or explicit DEMO_MODE session)
  const [sessionToken, setSessionToken] = useState(DEFAULT_DEMO_TOKEN);
  const [operatorId, setOperatorId] = useState(
    DEMO_MODE && DEFAULT_DEMO_TOKEN ? 'DEMO_RESPONDER_01' : '',
  );
  const [emailInput, setEmailInput] = useState('');
  const [passwordInput, setPasswordInput] = useState('');
  const [demoTokenInput, setDemoTokenInput] = useState(DEFAULT_DEMO_TOKEN);

  // Operational & SLA telemetry
  const [audioEnabled, setAudioEnabled] = useState(false);
  const [lastRealtimeLatencyMs, setLastRealtimeLatencyMs] = useState(null);
  const [error, setError] = useState('');
  const audioArmedRef = useRef(false);

  useEffect(() => {
    audioArmedRef.current = audioEnabled;
  }, [audioEnabled]);

  // 1. Subscribe to Supabase Auth session
  useEffect(() => {
    if (!supabase) return undefined;
    supabase.auth.getSession().then(({ data }) => {
      const sess = data?.session;
      if (sess?.access_token) {
        setSessionToken(sess.access_token);
        setOperatorId(sess.user?.email || sess.user?.id || 'RESPONDER_AUTH');
      }
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, sess) => {
      if (sess?.access_token) {
        setSessionToken(sess.access_token);
        setOperatorId(sess.user?.email || sess.user?.id || 'RESPONDER_AUTH');
      } else if (!DEMO_MODE) {
        setSessionToken('');
        setOperatorId('');
      }
    });
    return () => sub?.subscription?.unsubscribe();
  }, []);

  // 2. Fetch incidents list
  const refreshIncidents = useCallback(async () => {
    if (!supabase) {
      if (DEMO_MODE) {
        setIncidents(DEMO_INCIDENTS);
        setCameras(DEMO_CAMERAS);
        setSelected((curr) => {
          if (curr) {
            const updated = DEMO_INCIDENTS.find((x) => x.id === curr.id);
            if (updated) return updated;
          }
          const sorted = sortIncidentsByUrgency(
            DEMO_INCIDENTS.filter((x) => x.status !== 'RESOLVED'),
          );
          return sorted[0] || DEMO_INCIDENTS[0] || null;
        });
        return;
      }
      setError(
        'Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to connect to Supabase Realtime.',
      );
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

  // 3. Incremental Realtime subscription for `incidents`
  useEffect(() => {
    refreshIncidents();
    if (!supabase) return undefined;
    const channel = supabase
      .channel('mokgosi-incidents-live')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'incidents' },
        (payload) => {
          const nowMs = Date.now();
          if (payload.eventType === 'INSERT' && payload.new) {
            const createdMs = new Date(payload.new.created_at || nowMs).getTime();
            const latency = Math.max(12, Math.min(999, nowMs - createdMs));
            setLastRealtimeLatencyMs(latency);
            setIncidents((prev) => {
              const filtered = prev.filter((item) => item.id !== payload.new.id);
              return [payload.new, ...filtered];
            });

            const isGbv = isGbvIncident(payload.new);
            // Switch pillar automatically if critical GBV alert arrives
            if (isGbv && payload.new.priority === 'P1_CRITICAL') {
              setActivePillar('GBV_RESPONSE');
            }

            if (payload.new.priority === 'P1_CRITICAL') {
              setSelected(payload.new);
              setActiveTab('ACTIVE');
              if (audioArmedRef.current) {
                playCriticalAlertTone();
              }
            } else {
              setSelected((curr) => curr || payload.new);
            }
          } else if (payload.eventType === 'UPDATE' && payload.new) {
            setIncidents((prev) =>
              prev.map((item) => (item.id === payload.new.id ? payload.new : item)),
            );
            setSelected((curr) => (curr?.id === payload.new.id ? payload.new : curr));
            if (payload.new.priority === 'P1_CRITICAL' && audioArmedRef.current) {
              playCriticalAlertTone();
            }
          }
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [refreshIncidents]);

  // 4. Fetch & subscribe incrementally to selected incident context
  useEffect(() => {
    if (!selected) return undefined;
    let mounted = true;

    if (sessionToken) {
      postIncidentAudit(selected.id, 'VIEW_INCIDENT', sessionToken);
    }

    // Fetch consents & referrals for GBV context
    fetchSurvivorConsents(selected.user_id, sessionToken).then((c) => {
      if (mounted) setSurvivorConsents(c);
    });
    fetchIncidentReferrals(selected.id, sessionToken).then((res) => {
      if (mounted) setIncidentReferralsList(res?.referrals || []);
    });

    if (!supabase) {
      if (DEMO_MODE) {
        setCameras(DEMO_CAMERAS);
        setLocations(DEMO_BREADCRUMBS[selected.id] || []);
      }
      return undefined;
    }

    (async () => {
      const [camRes, locRes, logRes, manRes] = await Promise.all([
        supabase.rpc('get_authorized_nearby_cameras', {
          inc_lat: selected.lat,
          inc_lng: selected.lng,
          radius_m: 150,
        }),
        supabase
          .from('incident_locations')
          .select('*')
          .eq('incident_id', selected.id)
          .order('captured_at_utc', { ascending: true }),
        supabase
          .from('evidence_audit_logs')
          .select('*')
          .eq('incident_id', selected.id)
          .order('timestamp_utc', { ascending: true }),
        supabase
          .from('evidence_manifests')
          .select('*')
          .eq('incident_id', selected.id)
          .order('server_receipt_utc', { ascending: true }),
      ]);
      if (!mounted) return;
      setCameras(camRes.data || []);
      setLocations(locRes.data || []);
      setLogs(logRes.data || []);
      setManifests(manRes.data || []);
    })();

    const detailChannel = supabase
      .channel(`mokgosi-incident-${selected.id}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'evidence_manifests',
          filter: `incident_id=eq.${selected.id}`,
        },
        (payload) => {
          if (payload.new) {
            setManifests((prev) =>
              prev.some((m) => m.id === payload.new.id) ? prev : [...prev, payload.new],
            );
          }
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'evidence_audit_logs',
          filter: `incident_id=eq.${selected.id}`,
        },
        (payload) => {
          if (payload.new) {
            setLogs((prev) =>
              prev.some((l) => l.id === payload.new.id) ? prev : [...prev, payload.new],
            );
          }
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'incident_locations',
          filter: `incident_id=eq.${selected.id}`,
        },
        (payload) => {
          if (payload.new) {
            setLocations((prev) => [...prev, payload.new]);
          }
        },
      )
      .subscribe();

    return () => {
      mounted = false;
      supabase.removeChannel(detailChannel);
    };
  }, [selected?.id, selected?.lat, selected?.lng, selected?.user_id, sessionToken]);

  // 5. Computed SLA metrics and Pillar counts for HeaderBar
  const { openP1Count, medianAckSeconds, saferActiveCount, gbvActiveCount } = useMemo(() => {
    const active = incidents.filter((i) => i.status !== 'RESOLVED');
    const openP1 = active.filter((i) => i.priority === 'P1_CRITICAL').length;
    const saferActive = active.filter((i) => !isGbvIncident(i)).length;
    const gbvActive = active.filter((i) => isGbvIncident(i)).length;

    const ackDurations = incidents
      .filter((i) => i.created_at && i.acknowledged_at)
      .map((i) =>
        Math.max(
          0,
          Math.round(
            (new Date(i.acknowledged_at).getTime() - new Date(i.created_at).getTime()) /
              1000,
          ),
        ),
      )
      .sort((a, b) => a - b);
    let median = null;
    if (ackDurations.length > 0) {
      const mid = Math.floor(ackDurations.length / 2);
      median =
        ackDurations.length % 2 !== 0
          ? ackDurations[mid]
          : Math.round((ackDurations[mid - 1] + ackDurations[mid]) / 2);
    }
    return {
      openP1Count: openP1,
      medianAckSeconds: median,
      saferActiveCount: saferActive,
      gbvActiveCount: gbvActive,
    };
  }, [incidents]);

  function handlePillarChange(nextPillar) {
    setActivePillar(nextPillar);
    const activeInPillar = incidents
      .filter((i) => i.status !== 'RESOLVED')
      .filter((i) => (nextPillar === 'GBV_RESPONSE' ? isGbvIncident(i) : !isGbvIncident(i)));
    const sorted = sortIncidentsByUrgency(activeInPillar);
    if (sorted.length > 0) {
      setSelected(sorted[0]);
    } else {
      const anyInPillar = incidents.filter((i) =>
        nextPillar === 'GBV_RESPONSE' ? isGbvIncident(i) : !isGbvIncident(i),
      );
      setSelected(anyInPillar[0] || null);
    }
  }

  async function handleResponderSignIn(e) {
    e.preventDefault();
    setError('');
    if (DEMO_MODE && demoTokenInput.trim()) {
      setSessionToken(demoTokenInput.trim());
      setOperatorId(emailInput.trim() || 'DEMO_RESPONDER_01');
      return;
    }
    if (!supabase) {
      setError('Supabase client is not configured.');
      return;
    }
    const { data, error: signErr } = await supabase.auth.signInWithPassword({
      email: emailInput.trim(),
      password: passwordInput,
    });
    if (signErr) {
      setError(signErr.message);
      return;
    }
    if (data?.session) {
      setSessionToken(data.session.access_token);
      setOperatorId(data.user?.email || data.user?.id || 'RESPONDER');
    }
  }

  async function handleSignOut() {
    if (supabase) {
      await supabase.auth.signOut();
    }
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
        setIncidents((prev) =>
          prev.map((i) => (i.id === res.incident.id ? res.incident : i)),
        );
        if (selected?.id === target.id) {
          setSelected(res.incident);
        }
        if (res.incident.status === 'RESOLVED' && selected?.id === target.id) {
          setActiveTab('RESOLVED');
        }
        return;
      }
    } catch (err) {
      if (DEMO_MODE) {
        const updated = {
          ...target,
          status: nextStatus,
          acknowledged_by:
            nextStatus === 'ACKNOWLEDGED'
              ? operatorId || 'DEMO_RESPONDER_01'
              : target.acknowledged_by,
          acknowledged_at:
            nextStatus === 'ACKNOWLEDGED' ? new Date().toISOString() : target.acknowledged_at,
          assigned_to:
            nextStatus === 'ASSIGNED'
              ? operatorId || 'DEMO_RESPONDER_01'
              : target.assigned_to,
          assigned_at:
            nextStatus === 'ASSIGNED' ? new Date().toISOString() : target.assigned_at,
          dispatched_at:
            nextStatus === 'DISPATCHED' ? new Date().toISOString() : target.dispatched_at,
          resolved_at:
            nextStatus === 'RESOLVED' ? new Date().toISOString() : target.resolved_at,
        };
        setIncidents((prev) => prev.map((i) => (i.id === target.id ? updated : i)));
        if (selected?.id === target.id) {
          setSelected(updated);
          if (nextStatus === 'RESOLVED') {
            setActiveTab('RESOLVED');
          }
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
        setIncidents((prev) =>
          prev.map((i) => (i.id === res.incident.id ? res.incident : i)),
        );
        setSelected(res.incident);
      } else if (res?.ai_context) {
        setSelected((curr) => (curr ? { ...curr, ai_context: res.ai_context } : curr));
      }
      if (res?.signed_manifest) {
        setManifests((prev) => [...prev, res.signed_manifest]);
      }
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleRecordReferral(partnerId, notes) {
    if (!selected || !sessionToken) return;
    const res = await postIncidentReferral(selected.id, partnerId, notes, sessionToken);
    if (res?.referral) {
      setIncidentReferralsList((prev) => [res.referral, ...prev]);
    }
  }

  function handleOpenCameraModal(camera) {
    setActiveCameraModal(camera);
    if (selected && sessionToken) {
      postIncidentAudit(selected.id, 'OPEN_CCTV_STREAM', sessionToken);
    }
  }

  async function handleCaptureSnapshot(cameraId) {
    if (!selected) return null;
    const res = await postCctvSnapshot(selected.id, cameraId, sessionToken);
    if (res?.manifest) {
      setManifests((prev) => [...prev, res.manifest]);
    }
    return res;
  }

  function handleOpenDocketModal() {
    setDocketModalOpen(true);
    if (selected && sessionToken) {
      postIncidentAudit(selected.id, 'VIEW_EVIDENCE', sessionToken);
    }
  }

  const handleSelectIncident = useCallback((inc) => {
    if (!inc) return;
    setSelected(inc);
    if (isGbvIncident(inc)) {
      setActivePillar('GBV_RESPONSE');
    } else {
      setActivePillar('SAFER_COMMUNITIES');
      setSaferSubView('TACTICAL_MAP');
    }
  }, []);

  const expectedNextStatus = selected ? NEXT_STATUS[selected.status] : null;
  const aiModelLabel = selected?.ai_context?.model
    ? selected.ai_context.model === 'DETERMINISTIC_DEMO'
      ? 'DEMO PROFILE (DETERMINISTIC_DEMO — NOT YAMNET)'
      : selected.ai_context.model
    : 'NO MODEL INVOKED';

  const isGbvSelected = selected && isGbvIncident(selected);

  return (
    <main className="command-app">
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
        onSignOut={operatorId ? handleSignOut : null}
        activePillar={activePillar}
        onPillarChange={handlePillarChange}
        saferCount={saferActiveCount}
        gbvCount={gbvActiveCount}
      />

      {error && (
        <div className="notice" role="alert">
          <span>{error}</span>
          <button type="button" className="btn-ghost" onClick={() => setError('')}>
            Dismiss
          </button>
        </div>
      )}

      {!operatorId && (
        <section className="auth-banner" aria-label="Responder Authentication">
          <form className="auth-form" onSubmit={handleResponderSignIn}>
            <strong>Responder Sign-In Required for Lifecycle, CCTV &amp; Audit Writes</strong>
            <input
              type="text"
              placeholder="Responder email or ID"
              value={emailInput}
              onChange={(e) => setEmailInput(e.target.value)}
            />
            {!DEMO_MODE ? (
              <input
                type="password"
                placeholder="Supabase password"
                value={passwordInput}
                onChange={(e) => setPasswordInput(e.target.value)}
              />
            ) : (
              <input
                type="password"
                placeholder="DEMO_RESPONDER_TOKEN (or Bearer token)"
                value={demoTokenInput}
                onChange={(e) => setDemoTokenInput(e.target.value)}
              />
            )}
            <button type="submit">Authenticate Responder</button>
          </form>
        </section>
      )}

      <div className="layout">
        <IncidentQueue
          incidents={incidents}
          selectedId={selected?.id}
          onSelect={handleSelectIncident}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          activePillar={activePillar}
        />

        <section className="details" aria-label="Selected Incident Details">
          {activePillar === 'SAFER_COMMUNITIES' && (
            <div className="subview-bar" role="tablist">
              <button
                type="button"
                className={`subview-btn ${saferSubView === 'LIVE_MAP' ? 'active' : ''}`}
                onClick={() => setSaferSubView('LIVE_MAP')}
              >
                Citywide Live Map
              </button>
              <button
                type="button"
                className={`subview-btn ${saferSubView === 'TACTICAL_MAP' ? 'active' : ''}`}
                onClick={() => setSaferSubView('TACTICAL_MAP')}
              >
                Tactical Live Map
              </button>
              <button
                type="button"
                className={`subview-btn ${saferSubView === 'HOTSPOTS' ? 'active' : ''}`}
                onClick={() => setSaferSubView('HOTSPOTS')}
              >
                Community Hotspots &amp; Density (Aggregated)
              </button>
            </div>
          )}

          {activePillar === 'SAFER_COMMUNITIES' && saferSubView === 'HOTSPOTS' ? (
            <HotspotsView onBackToLiveMap={() => setSaferSubView('LIVE_MAP')} />
          ) : activePillar === 'SAFER_COMMUNITIES' && saferSubView === 'LIVE_MAP' ? (
            <LiveOperationsMap
              incidents={incidents}
              selectedId={selected?.id}
              onSelectIncident={handleSelectIncident}
              onLifecycle={handleLifecycle}
              cameras={cameras.length > 0 ? cameras : DEMO_CAMERAS}
              onOpenCameraStream={handleOpenCameraModal}
              activePillar={activePillar}
            />
          ) : selected ? (
            <>

              {selected.trigger_type === 'DURESS_PIN' && (
                <div className="duress-banner" role="alert">
                  <strong>
                    ⚠️ SILENT DURESS — do NOT call or message the user
                  </strong>
                  <span>
                    Survivor entered covert Duress PIN (0852). Their screen displays a
                    neutral “Journey Completed” decoy. Any outbound call or SMS to the
                    device risks exposing the survivor to an assailant.
                  </span>
                </div>
              )}

              <div className="panel">
                <div className="title">
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
                      <button
                        type="button"
                        className="btn-ghost"
                        style={{ padding: '3px 8px', fontSize: '11px', border: '1px solid var(--color-border)', borderRadius: '4px', cursor: 'pointer' }}
                        onClick={() => setSaferSubView('LIVE_MAP')}
                      >
                        ← Citywide Map
                      </button>
                    </div>
                    <h2>
                      Incident #{selected.id.slice(0, 8)} · {selected.trigger_type}
                    </h2>
                    <small>
                      Category: <b>{selected.category || 'PERSONAL_SAFETY'}</b> · Trusted
                      contact:{' '}
                      <b>{selected.trusted_contact_phone || 'Not configured'}</b>
                    </small>
                    <div className="lifecycle-chain">
                      <span>
                        Ack: <b>{selected.acknowledged_by || 'Pending'}</b>
                      </span>
                      <span>
                        Assigned: <b>{selected.assigned_to || 'Pending'}</b>
                      </span>
                      <span>
                        Dispatched:{' '}
                        <b>
                          {selected.dispatched_at
                            ? new Date(selected.dispatched_at).toLocaleTimeString()
                            : 'Pending'}
                        </b>
                      </span>
                      <span>
                        Resolved:{' '}
                        <b>
                          {selected.resolved_at
                            ? new Date(selected.resolved_at).toLocaleTimeString()
                            : 'Open'}
                        </b>
                      </span>
                    </div>
                  </div>

                  <div className="actions" aria-label="Responder Lifecycle Controls">
                    <button
                      type="button"
                      disabled={expectedNextStatus !== 'ACKNOWLEDGED' || !sessionToken}
                      onClick={() => handleLifecycle('ACKNOWLEDGED')}
                    >
                      1. Acknowledge
                    </button>
                    <button
                      type="button"
                      disabled={expectedNextStatus !== 'ASSIGNED' || !sessionToken}
                      onClick={() => handleLifecycle('ASSIGNED')}
                    >
                      2. Assign
                    </button>
                    <button
                      type="button"
                      disabled={expectedNextStatus !== 'DISPATCHED' || !sessionToken}
                      onClick={() => handleLifecycle('DISPATCHED')}
                    >
                      3. Dispatch Unit
                    </button>
                    <button
                      type="button"
                      className="muted"
                      disabled={expectedNextStatus !== 'RESOLVED' || !sessionToken}
                      onClick={() => handleLifecycle('RESOLVED')}
                    >
                      4. Resolve
                    </button>
                    <button
                      type="button"
                      className="btn-outline"
                      onClick={handleOpenDocketModal}
                    >
                      Inspect Full Evidence Docket
                    </button>
                  </div>
                </div>

                {!isGbvSelected && (
                  <div className="ai">
                    <div>
                      <b>
                        AI Acoustic &amp; Sensor Context · Escalation Aid Only ({aiModelLabel})
                      </b>
                      <p>
                        Status: {selected.ai_context?.status || 'AWAITING_OR_BYPASSED'} · Tags:{' '}
                        {(selected.ai_context?.tags || []).join(', ') || 'No tags'}
                        {selected.ai_context?.reason ? ` (${selected.ai_context.reason})` : ''}
                      </p>
                    </div>

                    {DEMO_MODE && (
                      <div className="actions">
                        <button
                          type="button"
                          className="danger"
                          disabled={!sessionToken}
                          onClick={() => handleAcousticSimulation('DISTRESSED')}
                        >
                          DEMO: Distress Profile
                        </button>
                        <button
                          type="button"
                          className="muted"
                          disabled={!sessionToken}
                          onClick={() => handleAcousticSimulation('SILENT')}
                        >
                          DEMO: Silent Coercion
                        </button>
                        <button
                          type="button"
                          className="muted"
                          disabled={!sessionToken}
                          onClick={() => handleAcousticSimulation('CONVERSATION')}
                        >
                          DEMO: Conversation
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>

              {/* Pillar B View (GBV Cases) */}
              {isGbvSelected ? (
                <GbvCaseView
                  incident={selected}
                  allIncidents={incidents}
                  consents={survivorConsents}
                  referrals={incidentReferralsList}
                  manifests={manifests}
                  logs={logs}
                  cameras={cameras}
                  locations={locations}
                  onRecordReferral={handleRecordReferral}
                  onOpenDocket={handleOpenDocketModal}
                  onOpenCameraStream={handleOpenCameraModal}
                />
              ) : (
                /* Pillar A View (Public Safety / Safer Communities) */
                <>
                  <TacticalMap
                    incident={selected}
                    locations={locations}
                    cameras={cameras}
                    onOpenCameraStream={handleOpenCameraModal}
                  />

                  <EvidenceDocketModal manifests={manifests} logs={logs} />
                </>
              )}
            </>
          ) : (
            activePillar === 'SAFER_COMMUNITIES' ? (
              <LiveOperationsMap
                incidents={incidents}
                selectedId={selected?.id}
                onSelectIncident={handleSelectIncident}
                onLifecycle={handleLifecycle}
                cameras={cameras.length > 0 ? cameras : DEMO_CAMERAS}
                onOpenCameraStream={handleOpenCameraModal}
                activePillar={activePillar}
              />
            ) : (
              <div className="panel empty">
                No incident selected in this pillar. Incoming SOS, Duress, and Check-In alerts appear here automatically.
              </div>
            )
          )}
        </section>
      </div>

      {activeCameraModal && selected && (
        <CctvStreamModal
          camera={activeCameraModal}
          incidentId={selected.id}
          onClose={() => setActiveCameraModal(null)}
          onCaptureSnapshot={handleCaptureSnapshot}
        />
      )}

      {docketModalOpen && selected && (
        <EvidenceDocketModal
          manifests={manifests}
          logs={logs}
          isModal
          onClose={() => setDocketModalOpen(false)}
        />
      )}
    </main>
  );
}
