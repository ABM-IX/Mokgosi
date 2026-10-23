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
  activePillar = 'SAFER_COMMUNITIES',
  onPillarChange,
  saferCount = 0,
  gbvCount = 0,
}) {
  return (
    <header className="command-header" role="banner">
      <div className="brand-block">
        <div className="brand">
          MOKGOSI <span>TWO-PILLAR COMMAND CONSOLE</span>
          {demoMode && <em className="demo-pill">DEMO MODE</em>}
        </div>
        <small>Pillar A: Safer Communities · Pillar B: GBV Response</small>
      </div>

      {onPillarChange && (
        <nav className="pillar-switcher" role="tablist" aria-label="Product Pillars">
          <button
            type="button"
            role="tab"
            aria-selected={activePillar === 'SAFER_COMMUNITIES'}
            className={`pillar-tab ${activePillar === 'SAFER_COMMUNITIES' ? 'active' : ''}`}
            onClick={() => onPillarChange('SAFER_COMMUNITIES')}
          >
            <span className="pillar-icon">🛡️</span>
            <span className="pillar-name">Safer Communities</span>
            <span className="pillar-count">{saferCount}</span>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={activePillar === 'GBV_RESPONSE'}
            className={`pillar-tab pillar-gbv ${activePillar === 'GBV_RESPONSE' ? 'active' : ''}`}
            onClick={() => onPillarChange('GBV_RESPONSE')}
          >
            <span className="pillar-icon">🟣</span>
            <span className="pillar-name">GBV Response</span>
            <span className="pillar-count">{gbvCount}</span>
          </button>
        </nav>
      )}

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

