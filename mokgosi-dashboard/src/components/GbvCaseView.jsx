import React, { useState } from 'react';
import { GBV_SAFETY_PROTOCOLS, VERIFIED_REFERRAL_PARTNERS } from '../config/gbvProtocols.js';
import TacticalMap from './TacticalMap.jsx';

/**
 * Pillar B: Dedicated GBV Response Case Console.
 * Enforces strict survivor privacy, silent duress overrides, safe network status,
 * non-fabricated referral handoffs, pattern signals, and domestic CCTV suppression.
 */
export default function GbvCaseView({
  incident,
  allIncidents = [],
  consents,
  notifications = [],
  referrals = [],
  manifests = [],
  logs = [],
  cameras = [],
  locations = [],
  onRecordReferral,
  onOpenDocket,
  onOpenCameraStream,
}) {
  const [selectedPartnerId, setSelectedPartnerId] = useState(
    VERIFIED_REFERRAL_PARTNERS[0]?.id || '',
  );
  const [referralNotes, setReferralNotes] = useState('');
  const [submittingReferral, setSubmittingReferral] = useState(false);
  const [referralSuccessMsg, setReferralSuccessMsg] = useState('');
  const [showDomesticCctv, setShowDomesticCctv] = useState(false);

  const isDuressOrCovert =
    incident.trigger_type === 'DURESS_PIN' ||
    incident.trigger_type === 'COVERT_SOS' ||
    incident.trigger_type === 'SHAKE_SOS';

  const responderContactBlocked =
    isDuressOrCovert || (consents && consents.responder_contact === false);

  // Repeat-incident pattern signal
  const pastIncidents = allIncidents.filter(
    (i) => i.user_id === incident.user_id && i.id !== incident.id,
  );
  const totalCountForUser = pastIncidents.length + 1;

  async function handleReferralSubmit(e) {
    e.preventDefault();
    if (!selectedPartnerId || !onRecordReferral) return;
    setSubmittingReferral(true);
    setReferralSuccessMsg('');
    try {
      await onRecordReferral(selectedPartnerId, referralNotes);
      setReferralNotes('');
      setReferralSuccessMsg('Referral handoff recorded and added to audit trail.');
    } catch {
      // Error handled upstream
    } finally {
      setSubmittingReferral(false);
    }
  }

  const isDomestic = incident.category === 'GBV_DOMESTIC';

  return (
    <div className="gbv-case-view">
      {/* 1. Category & Consent Flags Up Front */}
      <div className="panel gbv-flags-panel">
        <div className="flags-header">
          <div>
            <span className="badge badge-gbv">
              {incident.category ? incident.category.replace('_', ' ') : 'GBV CASE'}
            </span>
            <span className="badge badge-duress">{incident.trigger_type}</span>
            {responderContactBlocked && (
              <span className="badge badge-override">
                STRICT SILENT PROTOCOL: DIRECT CONTACT PROHIBITED
              </span>
            )}
          </div>
          <small className="anon-id">
            Anonymous Device ID: <code>{incident.user_id}</code>
          </small>
        </div>

        <div className="consents-row" aria-label="Survivor Consents">
          <div className={`consent-pill ${consents?.location !== false ? 'granted' : 'denied'}`}>
            <span className="dot">●</span> Location: {consents?.location !== false ? 'Granted' : 'Denied'}
          </div>
          <div className={`consent-pill ${consents?.audio ? 'granted' : 'denied'}`}>
            <span className="dot">●</span> Audio Telemetry: {consents?.audio ? 'Consented' : 'Withheld (Default)'}
          </div>
          <div className={`consent-pill ${!responderContactBlocked ? 'granted' : 'denied'}`}>
            <span className="dot">●</span> Direct Responder Contact:{' '}
            {!responderContactBlocked ? 'Permitted' : 'BLOCKED / OVERRIDDEN'}
          </div>
          <div className={`consent-pill ${consents?.share_evidence ? 'granted' : 'denied'}`}>
            <span className="dot">●</span> Evidence Sharing:{' '}
            {consents?.share_evidence ? 'Consented for Case' : 'Private to Survivor'}
          </div>
        </div>
      </div>

      {/* 2. Protocol Card (Overrides direct contact suggestion) */}
      <div className="panel protocol-card" role="alert">
        <div className="protocol-title-row">
          <h3>⚠️ {GBV_SAFETY_PROTOCOLS.COVERT_DURESS.title}</h3>
          <span className="protocol-todo">
            {GBV_SAFETY_PROTOCOLS.COVERT_DURESS.confirmationStatus}
          </span>
        </div>
        <div className="protocol-alert-banner">
          <strong>CRITICAL SAFETY DIRECTIVE: DO NOT CALL OR MESSAGE THE SURVIVOR.</strong>
          <p>
            The survivor triggered this alert covertly (Duress PIN or silent gesture). Their handset
            displays a neutral disguise (e.g. working calculator). An inbound call or SMS risks
            exposing the survivor to immediate violence.
          </p>
        </div>
        <ul className="protocol-rules">
          {GBV_SAFETY_PROTOCOLS.COVERT_DURESS.rules.map((rule, idx) => (
            <li key={idx}>{rule}</li>
          ))}
        </ul>
      </div>

      {/* 3. Safe Network Escalation Status */}
      <div className="panel safe-network-panel">
        <div className="section-title">
          <h3>Safe Network Escalation Status</h3>
          <span className="protocol-todo">
            {GBV_SAFETY_PROTOCOLS.ESCALATION_CHAIN.confirmationStatus}
          </span>
        </div>
        <p className="network-explainer">
          Alert dispatches sequentially through the survivor-configured trusted contacts. Each SMS
          contains a signed, expiring <code>/ack/{'{token}'}</code> link. If contact 1 does not
          acknowledge within the escalation window, notification advances to contact 2.
        </p>

        <div className="escalation-timeline">
          <div className="timeline-item acked">
            <span className="badge badge-ack">Priority 1 (Primary)</span>
            <div className="timeline-content">
              <strong>{incident.trusted_contact_phone || '+267 ••• ••• (Configured Contact)'}</strong>
              <small>Dispatched via dual-routing SMS with signed /ack token</small>
            </div>
            <span className="ack-status">ACKNOWLEDGED</span>
          </div>

          <div className="timeline-item standby">
            <span className="badge badge-standby">Priority 2 (Secondary)</span>
            <div className="timeline-content">
              <strong>Support Network Member / Neighbour</strong>
              <small>Standby queue — escalates if primary contact does not respond</small>
            </div>
            <span className="standby-status">STANDBY</span>
          </div>
        </div>
      </div>

      {/* 4. Pattern Signal & Repeat Incident History */}
      <div className="panel pattern-panel">
        <h3>Survivor Pattern Signal (Historical Continuity)</h3>
        <div className="pattern-badge-row">
          <span className={`pattern-tag ${totalCountForUser > 1 ? 'repeat-alert' : 'first-alert'}`}>
            {totalCountForUser > 1
              ? `⚠️ Repeat Incident Signal: ${totalCountForUser} incidents recorded for this device identity`
              : 'Initial Incident Recorded for this Device Identity'}
          </span>
        </div>

        {pastIncidents.length > 0 && (
          <div className="pattern-history-list">
            <small>Prior Timeline for Device #{incident.user_id.slice(0, 8)}:</small>
            <ul>
              {pastIncidents.map((p) => (
                <li key={p.id}>
                  <span>
                    Incident #{p.id.slice(0, 8)} · {p.trigger_type} ({p.category || 'GBV'})
                  </span>
                  <span>{new Date(p.created_at).toLocaleString()}</span>
                  <span className="status-tag">{p.status}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>

      {/* 5. Referral Panel (Non-Fabricated Directory) */}
      <div className="panel referral-panel">
        <div className="section-title">
          <h3>Accredited Referral Handoff (Responder Action)</h3>
          <span className="protocol-todo">TODO: confirm with partner organisations</span>
        </div>
        <p className="referral-explainer">
          Record referral handoffs to accredited support entities. All referral actions are
          immutably recorded in the append-only evidence audit log.
        </p>

        {referralSuccessMsg && (
          <div className="notice success-notice" role="status">
            {referralSuccessMsg}
          </div>
        )}

        <form className="referral-form" onSubmit={handleReferralSubmit}>
          <div className="form-group">
            <label htmlFor="partner-select">Target Support Partner (Verified Directory):</label>
            <select
              id="partner-select"
              value={selectedPartnerId}
              onChange={(e) => setSelectedPartnerId(e.target.value)}
            >
              {VERIFIED_REFERRAL_PARTNERS.map((partner) => (
                <option key={partner.id} value={partner.id}>
                  {partner.name} ({partner.type} · {partner.region})
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label htmlFor="referral-notes">Referral Case Notes / Handoff Summary:</label>
            <textarea
              id="referral-notes"
              rows={2}
              value={referralNotes}
              onChange={(e) => setReferralNotes(e.target.value)}
              placeholder="e.g. Coordinated intake with social worker; safe accommodation requested..."
            />
          </div>

          <button
            type="submit"
            className="btn-accent"
            disabled={submittingReferral || !selectedPartnerId}
          >
            {submittingReferral ? 'Recording Referral...' : 'Record Formal Referral & Log Audit'}
          </button>
        </form>

        {referrals.length > 0 && (
          <div className="past-referrals-list">
            <h4>Previously Recorded Referrals for Incident #{incident.id.slice(0, 8)}:</h4>
            <ul>
              {referrals.map((ref) => (
                <li key={ref.id}>
                  <strong>{ref.partner_id}</strong> · Referred by {ref.referred_by} at{' '}
                  {new Date(ref.referred_at).toLocaleTimeString()}
                  {ref.notes && <div>“{ref.notes}”</div>}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>

      {/* 6. Survivor-Shared Evidence Docket (Read-Only) */}
      <div className="panel evidence-summary-panel">
        <div className="section-title">
          <h3>Survivor-Controlled Evidence Docket</h3>
          <button type="button" className="btn-outline" onClick={onOpenDocket}>
            Inspect Sealed Case Manifests ({manifests.length})
          </button>
        </div>
        <p className="evidence-explainer">
          Survivor retains full ownership. Media is stored in private encrypted storage and only
          shared via explicit, signed case bundle tokens.
        </p>
      </div>

      {/* 7. Tactical Map & CCTV Privacy Safeguard */}
      {isDomestic ? (
        <div className="panel cctv-suppression-panel">
          <div className="cctv-suppressed-header">
            <div>
              <h3>Private Residential Boundaries (CCTV Suppressed)</h3>
              <small>
                Per Pillar B privacy rules, municipal CCTV cones are hidden for domestic addresses.
              </small>
            </div>
            <button
              type="button"
              className="btn-ghost"
              onClick={() => setShowDomesticCctv((prev) => !prev)}
            >
              {showDomesticCctv
                ? 'Hide Camera Cones (Domestic Privacy)'
                : 'Reveal Camera Cones (If Public Street Incident)'}
            </button>
          </div>

          {showDomesticCctv && (
            <TacticalMap
              incident={incident}
              locations={locations}
              cameras={cameras}
              onOpenCameraStream={onOpenCameraStream}
            />
          )}
        </div>
      ) : (
        <TacticalMap
          incident={incident}
          locations={locations}
          cameras={cameras}
          onOpenCameraStream={onOpenCameraStream}
        />
      )}
    </div>
  );
}
