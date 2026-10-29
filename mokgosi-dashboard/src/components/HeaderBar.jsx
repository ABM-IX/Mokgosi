import React from 'react';
import Icon, { BrandMark } from './Icons.jsx';

const THEME_OPTIONS = [
  ['light', 'sun', 'Light'],
  ['system', 'monitor', 'Match this device'],
  ['dark', 'moon', 'Dark'],
];

/** Top bar: product, incident type switch, the two numbers a shift lead watches, and the operator. */
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
  themeMode = 'system',
  onThemeChange,
}) {
  const connection = meshOnline ? 'Live' : demoMode ? 'Sample data' : 'Not connected';
  return (
    <header className="topbar">
      <div className="topbar-brand">
        <BrandMark size={30} />
        <div className="topbar-name">
          <span className="wordmark">Mokgosi</span>
          <span className="topbar-product">Responder console</span>
        </div>
      </div>

      {onPillarChange && (
        <nav className="segmented" aria-label="Incident type">
          <button type="button" aria-pressed={activePillar === 'SAFER_COMMUNITIES'} onClick={() => onPillarChange('SAFER_COMMUNITIES')}>
            Public safety <span className="count">{saferCount}</span>
          </button>
          <button type="button" aria-pressed={activePillar === 'GBV_RESPONSE'} onClick={() => onPillarChange('GBV_RESPONSE')}>
            GBV <span className="count">{gbvCount}</span>
          </button>
        </nav>
      )}

      <div className="topbar-stats" aria-label="Shift summary">
        <div className={`stat ${openP1Count > 0 ? 'stat-critical' : ''}`}>
          <strong className="num">{openP1Count}</strong>
          <span>critical open</span>
        </div>
        <div className="stat">
          <strong className="num">{medianAckSeconds != null ? `${medianAckSeconds} s` : '—'}</strong>
          <span>median time to acknowledge</span>
        </div>
        {lastRealtimeLatencyMs != null && (
          <div className="stat">
            <strong className="num">{lastRealtimeLatencyMs} ms</strong>
            <span>last alert to arrive</span>
          </div>
        )}
      </div>

      <div className="topbar-user">
        <button
          type="button"
          className={`icon-btn ${audioEnabled ? 'is-on' : ''}`}
          aria-pressed={audioEnabled}
          title={audioEnabled ? 'Sound for critical alerts is on' : 'Turn on sound for critical alerts (browsers need one click first)'}
          aria-label={audioEnabled ? 'Turn off sound for critical alerts' : 'Turn on sound for critical alerts'}
          onClick={onToggleAudio}
        >
          <Icon name={audioEnabled ? 'bell' : 'bellOff'} />
        </button>

        {onThemeChange && (
          <div className="theme-switch" role="group" aria-label="Appearance">
            {THEME_OPTIONS.map(([value, icon, text]) => (
              <button key={value} type="button" aria-pressed={themeMode === value} title={text} aria-label={text} onClick={() => onThemeChange(value)}>
                <Icon name={icon} size={15} />
              </button>
            ))}
          </div>
        )}

        <span className={`connection ${meshOnline ? 'is-live' : ''}`}>{connection}</span>
        <span className="operator" title="Signed in as">
          {operatorId || 'Not signed in'}
        </span>
        {operatorId && onSignOut && (
          <button type="button" className="icon-btn" title="Sign out" aria-label="Sign out" onClick={onSignOut}>
            <Icon name="logOut" />
          </button>
        )}
      </div>
    </header>
  );
}
