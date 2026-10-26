import React, { useState } from 'react';

export default function LandingPortal({
  onSignIn,
  error,
  demoMode = false,
  meshOnline = true,
}) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [localError, setLocalError] = useState('');

  async function handleSubmit(e) {
    e.preventDefault();
    setLocalError('');
    if (!email.trim()) {
      setLocalError('Please enter your responder email or operator ID.');
      return;
    }
    if (!password && !demoMode) {
      setLocalError('Please enter your password.');
      return;
    }
    setLoading(true);
    try {
      await onSignIn(email.trim(), password);
    } catch (err) {
      setLocalError(err.message || 'Authentication failed');
    } finally {
      setLoading(false);
    }
  }

  function handleFillDemo() {
    setEmail('DISP_GABORONE_01');
    setPassword('mokgosi-demo-responder-secret-key-2026');
    setLocalError('');
  }

  const displayError = localError || error;

  return (
    <div className="landing-portal">
      {/* Top Navigation */}
      <header className="portal-header">
        <div className="portal-brand">
          <div className="portal-logo-badge">🛡️</div>
          <div>
            <div className="portal-title">MOKGOSI</div>
            <div className="portal-tagline">Your call for help. A connected response.</div>
          </div>
        </div>

        <div className="portal-nav-actions">
          <div className={`portal-status-pill ${meshOnline ? 'online' : 'offline'}`}>
            <span className="status-dot"></span>
            <span>{meshOnline ? 'Realtime Engine Active' : 'Connecting Engine...'}</span>
          </div>
          <a href="#login-section" className="portal-login-anchor-btn">
            Responder Portal ↓
          </a>
        </div>
      </header>

      {/* Hero Section */}
      <section className="portal-hero">
        <div className="portal-hero-badge">FNB Hackathon · Safer Communities &amp; GBV Response</div>
        <h1 className="portal-hero-heading">
          Two Pillars. One Fault-Tolerant Engine.
        </h1>
        <p className="portal-hero-lead">
          Mokgosi is an emergency coordination network for public safety and gender-based violence (GBV)
          crisis response in Botswana. By connecting citizens, trusted circles, municipal camera infrastructure,
          and accredited responders, response coordinates with zero single points of failure.
        </p>

        <div className="portal-stats-strip">
          <div className="portal-stat-card">
            <span className="stat-num">&lt; 1s</span>
            <span className="stat-desc">Realtime CAD Dispatch Latency</span>
          </div>
          <div className="portal-stat-card">
            <span className="stat-num">150m</span>
            <span className="stat-desc">PostGIS CCTV Spatial Matching</span>
          </div>
          <div className="portal-stat-card">
            <span className="stat-num">Ed25519</span>
            <span className="stat-desc">Cryptographic Evidence Vault</span>
          </div>
          <div className="portal-stat-card">
            <span className="stat-num">Dual-Path</span>
            <span className="stat-desc">Zero AI Single Point of Failure</span>
          </div>
        </div>
      </section>

      {/* Main Grid: Pillar Showcase & Login Gate */}
      <div className="portal-main-grid">
        {/* Left Column: What is Mokgosi & The Two Pillars */}
        <section className="portal-info-col">
          <div className="portal-section-header">
            <h2>The Two-Pillar Architecture</h2>
            <p>Built for real people facing real threats — both on the street and at home.</p>
          </div>

          <div className="pillar-cards-container">
            {/* Pillar A */}
            <article className="pillar-card pillar-a-card">
              <div className="pillar-card-header">
                <span className="pillar-badge pillar-a-badge">Pillar A · Public Space</span>
                <h3>Safer Communities</h3>
              </div>
              <p className="pillar-desc">
                Proactive public transit protection, municipal sensor mesh coordination, and coarse-grid community density analytics.
              </p>
              <ul className="pillar-features-list">
                <li>
                  <strong>Active Escort with Check-Ins:</strong> Timed transit mode with automatic 30s/15s check-in prompts and motion impact triggers.
                </li>
                <li>
                  <strong>150m CCTV Mesh:</strong> PostGIS spatial query pairs active SOS events with nearby authorized cameras, displaying directional FOV cones.
                </li>
                <li>
                  <strong>Community Hotspots:</strong> ~500m grid clustering with strict k-anonymity suppression (&lt; 5 incidents suppressed) to protect privacy.
                </li>
              </ul>
            </article>

            {/* Pillar B */}
            <article className="pillar-card pillar-b-card">
              <div className="pillar-card-header">
                <span className="pillar-badge pillar-b-badge">Pillar B · Private &amp; Domestic Space</span>
                <h3>Gender-Based Violence (GBV) Response</h3>
              </div>
              <p className="pillar-desc">
                Covert help-seeking, survivor-owned evidentiary custody, and priority safe-network escalation with strict non-retaliation invariants.
              </p>
              <ul className="pillar-features-list">
                <li>
                  <strong>Covert Calculator Disguise:</strong> Android launcher disguise with a working math engine, Safe PIN (<code>2580=</code>), and silent Duress PIN (<code>0852=</code>).
                </li>
                <li>
                  <strong>Silent Duress Protection:</strong> When triggered covertly, responders are strictly barred from direct calls/SMS to prevent retaliatory violence from assailants.
                </li>
                <li>
                  <strong>Survivor Evidence Vault:</strong> Client-side encrypted audio/photo/notes with Ed25519-signed manifests and 2h expiring bundle URLs.
                </li>
                <li>
                  <strong>Accredited Referral Directory:</strong> Verified partner handoff routing with honest flagging — zero fabricated hotline numbers.
                </li>
              </ul>
            </article>
          </div>

          {/* Architectural Invariants Card */}
          <div className="invariants-card">
            <h4>Core Engineering Invariants</h4>
            <div className="invariants-grid">
              <div className="invariant-item">
                <div className="inv-icon">⚡</div>
                <div>
                  <strong>No False Assurance</strong>
                  <p>Mobile client only claims delivery upon HTTP 2xx; otherwise it queues idempotently with SMS fallback.</p>
                </div>
              </div>
              <div className="invariant-item">
                <div className="inv-icon">🛡️</div>
                <div>
                  <strong>Survivor Owns the Data</strong>
                  <p>Evidence media remains strictly private to the survivor until explicitly shared via sealed case bundles.</p>
                </div>
              </div>
              <div className="invariant-item">
                <div className="inv-icon">📜</div>
                <div>
                  <strong>Append-Only Audit Logs</strong>
                  <p>Every case view, lifecycle transition, and referral handoff is recorded immutably in tamper-evident logs.</p>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Right Column: Responder Login Gate */}
        <section id="login-section" className="portal-login-col">
          <div className="login-card">
            <div className="login-card-header">
              <div className="login-badge">Restricted Access</div>
              <h2>Responder Command Center</h2>
              <p>Sign in to access real-time CAD dispatch, CCTV stream inspection, and case lifecycle triage.</p>
            </div>

            {displayError && (
              <div className="login-error-alert" role="alert">
                <span className="alert-icon">⚠️</span>
                <span>{displayError}</span>
              </div>
            )}

            <form onSubmit={handleSubmit} className="portal-login-form">
              <div className="form-group">
                <label htmlFor="portal-email">Responder Email or Operator ID</label>
                <input
                  id="portal-email"
                  type="text"
                  placeholder="e.g. responder@mokgosi.org or DISP_01"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="username"
                  required
                />
              </div>

              <div className="form-group">
                <label htmlFor="portal-password">Password or Secret Token</label>
                <input
                  id="portal-password"
                  type="password"
                  placeholder="Enter responder credentials"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete="current-password"
                  required={!demoMode}
                />
              </div>

              <button
                type="submit"
                className="btn-login-submit"
                disabled={loading}
              >
                {loading ? 'Authenticating...' : 'Sign In to Command Center →'}
              </button>

              {demoMode && (
                <div className="demo-credentials-helper">
                  <div className="helper-label">Demo &amp; Evaluation Mode Active</div>
                  <button
                    type="button"
                    className="btn-demo-autofill"
                    onClick={handleFillDemo}
                  >
                    Auto-Fill Demo Dispatcher Credentials
                  </button>
                  <small>Pre-loads verified test token for instant hackathon evaluation.</small>
                </div>
              )}
            </form>

            <div className="login-footer-security-note">
              <span>🔒 Encrypted connection to Supabase Auth &amp; PostGIS Tactical Engine</span>
            </div>
          </div>
        </section>
      </div>

      {/* Footer */}
      <footer className="portal-footer">
        <div>
          <strong>MOKGOSI EMERGENCY NETWORK</strong> · Built for FNB Hackathon
        </div>
        <div className="portal-footer-links">
          <span>Gaborone &amp; National Jurisdiction</span> · <span>Setswana &amp; English</span>
        </div>
      </footer>
    </div>
  );
}
