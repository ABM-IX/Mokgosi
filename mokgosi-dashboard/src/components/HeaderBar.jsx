import React from 'react';

/**
 * Top command bar displaying Mokgosi branding, SLA metrics (open P1 count,
 * median time-to-acknowledge, Realtime latency), audio alert gesture toggle,
 * and authenticated responder identity.
 */
export default function HeaderBar({
  meshOnline,
  demoMode,
  operatorId,
  openP1Count,
  medianAckSeconds,
  lastRealtimeLatencyMs,
  audioEnabled,
  onToggleAudio,
  onSignOut,
}) {
  return (
    <header className="command-header" role="banner">
      <div className="brand-block">
        <div className="brand">
          MOKGOSI <span>PERSONAL SAFETY &amp; RESPONSE NETWORK</span>
          {demoMode && <em className="demo-pill">DEMO MODE</em>}
        </div>
        <small>Your call for help. A connected response.</small>
      </div>

      <div className="sla-strip" aria-label="Operational SLA metrics">
        <div className={`sla-metric ${openP1Count > 0 ? 'sla-critical' : ''}`}>
          <span className="sla-label">OPEN P1 CRITICAL</span>
          <strong className="sla-value">{openP1Count}</strong>
        </div>
        <div className="sla-metric">
          <span className="sla-label">MEDIAN ACK SLA</span>
          <strong className="sla-value">
            {medianAckSeconds != null ? `${medianAckSeconds}s` : '—'}
          </strong>
        </div>
        <div className="sla-metric">
          <span className="sla-label">REALTIME LATENCY</span>
          <strong className="sla-value">
            {lastRealtimeLatencyMs != null ? `${lastRealtimeLatencyMs} ms` : '< 1000 ms'}
          </strong>
        </div>
      </div>

      <div className="operator-strip">
        <button
          type="button"
          className={`audio-toggle ${audioEnabled ? 'active' : ''}`}
          onClick={onToggleAudio}
          title="Browser requires a user click before playing P1 audible alerts"
        >
          {audioEnabled ? '🔊 P1 Audio Armed' : '🔇 Arm P1 Audio Alert'}
        </button>
        <span className={`mesh-status ${meshOnline ? 'online' : 'offline'}`}>
          ● {meshOnline ? 'POSTGIS MESH ONLINE' : 'DEMO / OFFLINE REHEARSAL'}
        </span>
        <span className="operator-badge" title="Authenticated responder identity">
          Operator: <b>{operatorId || 'UNAUTHENTICATED'}</b>
        </span>
        {operatorId && onSignOut && (
          <button type="button" className="btn-ghost" onClick={onSignOut}>
            Sign out
          </button>
        )}
      </div>
    </header>
  );
}

