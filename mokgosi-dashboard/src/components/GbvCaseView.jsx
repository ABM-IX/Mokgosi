import React, { useState } from 'react';
import { GBV_SAFETY_PROTOCOLS, VERIFIED_REFERRAL_PARTNERS } from '../config/gbvProtocols.js';
import { AUDIT_LABEL, STATUS_LABEL, TRIGGER_LABEL, clockTime, dateTime, isCovert, label } from '../lib/labels.js';
import TacticalMap from './TacticalMap.jsx';

const CONTACT_ACTIONS = new Set([
  'ESCALATION_NOTIFICATION_DISPATCHED',
  'TRUSTED_CONTACT_ALERTED',
  'TRUSTED_CONTACT_ACKNOWLEDGED',
  'TRUSTED_CONTACT_FAILED',
  'TRUSTED_CONTACT_DEMO_LOGGED',
  'TRUSTED_CONTACT_SKIPPED_NO_PROVIDER',
  'TRUSTED_CONTACT_NOT_CONFIGURED',
]);
const NOT_SENT_ACTIONS = new Set(['TRUSTED_CONTACT_DEMO_LOGGED', 'TRUSTED_CONTACT_SKIPPED_NO_PROVIDER']);

/** Case view for gender-based violence incidents. The do-not-contact warning sits above it, in IncidentSummary. */
export default function GbvCaseView({
  incident,
  allIncidents = [],
  consents,
  referrals = [],
  manifests = [],
  logs = [],
  cameras = [],
  locations = [],
  onRecordReferral,
  onOpenDocket,
  onOpenCameraStream,
}) {
  const [partnerId, setPartnerId] = useState(VERIFIED_REFERRAL_PARTNERS[0]?.id || '');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [saved, setSaved] = useState('');
  const [showMap, setShowMap] = useState(false);

  const covert = isCovert(incident);
  const contactBlocked = covert || !consents || consents.responder_contact === false;
  const earlier = allIncidents
    .filter((i) => i.user_id === incident.user_id && i.id !== incident.id)
    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  const contactEvents = logs.filter((log) => CONTACT_ACTIONS.has(log.action));
  const smsNotSetUp = contactEvents.some((log) => NOT_SENT_ACTIONS.has(log.action));
  const isHome = incident.category === 'GBV_DOMESTIC';
  const partnerName = (id) => VERIFIED_REFERRAL_PARTNERS.find((p) => p.id === id)?.name || id;

  async function handleReferral(e) {
    e.preventDefault();
    if (!partnerId || !onRecordReferral) return;
    setSubmitting(true);
    setSaved('');
    try {
      await onRecordReferral(partnerId, notes);
      setNotes('');
      setSaved('Referral recorded in the activity log.');
    } catch {
      // The console shows the error banner.
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <div className="grid-2">
        <section className="card" aria-label="Consent">
          <div className="card-head">
            <h2>What they have agreed to</h2>
          </div>
          <dl className="facts">
            <dt>Location</dt>
            <dd>{consents?.location === false ? 'Not shared' : 'Shared during alerts'}</dd>
            <dt>Audio</dt>
            <dd>{consents?.audio ? 'Recording allowed' : 'Not allowed'}</dd>
            <dt>Contact from responders</dt>
            <dd>{contactBlocked ? (covert ? 'Not allowed (silent alert)' : 'Not allowed') : 'Allowed'}</dd>
            <dt>Evidence</dt>
            <dd>{consents?.share_evidence ? 'Shared for this case' : 'Not shared'}</dd>
          </dl>
          {!consents && <p className="card-note">Their settings could not be loaded, so the safest defaults are shown.</p>}
        </section>

        <section className="card" aria-label="Trusted contacts">
          <div className="card-head">
            <h2>Trusted contacts</h2>
          </div>
          {contactEvents.length > 0 ? (
            <ul className="list-plain">
              {contactEvents.map((log) => (
                <li key={log.id}>
                  <span>
                    {label(AUDIT_LABEL, log.action)}
                    {log.client_metadata?.priority ? ` · contact ${log.client_metadata.priority}` : ''}
                  </span>
                  <span className="faint num">{clockTime(log.timestamp_utc)}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="muted">No record yet of a trusted contact being messaged about this alert.</p>
          )}
          {smsNotSetUp && <p className="card-note">SMS delivery is not set up on the server, so no message was sent.</p>}
          <p className="card-note">{GBV_SAFETY_PROTOCOLS.ESCALATION_CHAIN.description}</p>
        </section>
      </div>

      <section className="card" aria-label="Earlier alerts">
        <div className="card-head">
          <h2>Earlier alerts from this person</h2>
          {earlier.length > 0 && <span className="card-note">{earlier.length} before this one</span>}
        </div>
        {earlier.length > 0 ? (
          <ul className="list-plain">
            {earlier.map((past) => (
              <li key={past.id}>
                <span>{label(TRIGGER_LABEL, past.trigger_type)}</span>
                <span className="muted">
                  {label(STATUS_LABEL, past.status)} · {dateTime(past.created_at)}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted">This is the first alert from this person.</p>
        )}
      </section>

      <section className="card" aria-label="Referral">
        <div className="card-head">
          <h2>Refer to a support organisation</h2>
          <span className="card-note">None of these organisations has confirmed its details yet.</span>
        </div>
        <form className="field" onSubmit={handleReferral}>
          <label className="field">
            <span>Organisation</span>
            <select id="partner-select" value={partnerId} onChange={(e) => setPartnerId(e.target.value)}>
              {VERIFIED_REFERRAL_PARTNERS.map((partner) => (
                <option key={partner.id} value={partner.id}>
                  {partner.name}
                  {partner.verified ? '' : ' (not yet verified)'}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>Handover notes</span>
            <textarea
              id="referral-notes"
              rows={2}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="For example: asked for safe accommodation; one child with them."
            />
            <span className="field-hint">Referrals are added to the activity log and cannot be edited afterwards.</span>
          </label>
          <div className="row">
            <button type="submit" className="btn btn-primary" disabled={submitting || !partnerId}>
              {submitting ? 'Recording…' : 'Record referral'}
            </button>
            {saved && (
              <span className="muted" role="status">
                {saved}
              </span>
            )}
          </div>
        </form>
        {referrals.length > 0 && (
          <ul className="list-plain">
            {referrals.map((ref) => (
              <li key={ref.id}>
                <span>
                  {partnerName(ref.partner_id)}
                  {ref.notes ? <span className="muted"> · “{ref.notes}”</span> : null}
                </span>
                <span className="faint">
                  {ref.referred_by} · {clockTime(ref.referred_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card" aria-label="Shared evidence">
        <div className="card-head">
          <h2>Shared evidence</h2>
          <button type="button" className="btn btn-small" onClick={onOpenDocket}>
            Open evidence
          </button>
        </div>
        <p className="muted">
          {manifests.length > 0
            ? `${manifests.length} signed ${manifests.length === 1 ? 'record' : 'records'} attached to this incident.`
            : 'Nothing has been shared. Evidence stays on the person’s phone unless they choose to share it.'}
        </p>
      </section>

      {isHome && !showMap ? (
        <section className="card" aria-label="Location">
          <div className="card-head">
            <h2>Location</h2>
            <button type="button" className="btn btn-small" onClick={() => setShowMap(true)}>
              Show map and cameras
            </button>
          </div>
          <p className="muted">
            This may be a home address, so the map and nearby cameras are hidden until you open them. Open them only
            if the incident is on a public street.
          </p>
        </section>
      ) : (
        <TacticalMap incident={incident} locations={locations} cameras={cameras} onOpenCameraStream={onOpenCameraStream} />
      )}
    </>
  );
}
