import React from 'react';

/** Top bar: product name, incident type switch, the two numbers a shift lead watches, and the operator. */
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
  const connection = meshOnline ? 'Live' : demoMode ? 'Sample data' : 'Not connected';
  return (
    <header className="topbar">
      <div className="topbar-brand">
        <span className="wordmark">Mokgosi</span>
        <span className="topbar-product">Responder console</span>
      </div>

      {onPillarChange && (
        <nav className="segmented" aria-label="Incident type">
          <button
            type="button"
            aria-pressed={activePillar === 'SAFER_COMMUNITIES'}
            onClick={() => onPillarChange('SAFER_COMMUNITIES')}
          >
            Public safety <span className="count">{saferCount}</span>
          </button>
          <button
            type="button"
            aria-pressed={activePillar === 'GBV_RESPONSE'}
            onClick={() => onPillarChange('GBV_RESPONSE')}
          >
            GBV <span className="count">{gbvCount}</span>
          </button>
        </nav>
      )}

      <div className="topbar-stats" aria-label="Shift summary">
        <span className={openP1Count > 0 ? 'stat-critical' : undefined}>
          <strong>{openP1Count}</strong> critical open
        </span>
        <span>
          Median time to acknowledge <strong>{medianAckSeconds != null ? `${medianAckSeconds} s` : '—'}</strong>
        </span>
        {lastRealtimeLatencyMs != null && (
          <span>
            Last alert arrived in <strong>{lastRealtimeLatencyMs} ms</strong>
          </span>
        )}
      </div>

      <div className="topbar-user">
        <button
          type="button"
          className="btn btn-quiet btn-small"
          aria-pressed={audioEnabled}
          title="Browsers only allow sound after you click once"
          onClick={onToggleAudio}
        >
          Sound for critical alerts: {audioEnabled ? 'on' : 'off'}
        </button>
        <span className={`connection ${meshOnline ? 'is-live' : ''}`}>{connection}</span>
        <span className="operator" title="Signed in as">
          {operatorId || 'Not signed in'}
        </span>
        {operatorId && onSignOut && (
          <button type="button" className="btn btn-quiet btn-small" onClick={onSignOut}>
            Sign out
          </button>
        )}
      </div>
    </header>
  );
}
