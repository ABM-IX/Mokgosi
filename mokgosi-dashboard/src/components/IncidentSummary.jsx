import React from 'react';
import PriorityGlyph from './PriorityGlyph.jsx';
import { GBV_SAFETY_PROTOCOLS } from '../config/gbvProtocols.js';
import {
  CATEGORY_LABEL,
  NEXT_ACTION_LABEL,
  PRIORITY_CLASS,
  PRIORITY_LABEL,
  STATUS_LABEL,
  STATUS_ORDER,
  TRIGGER_LABEL,
  clockTime,
  coords,
  formatPhone,
  isCovert,
  label,
  shortId,
  timeAgo,
} from '../lib/labels.js';

const NEXT_STATUS = { CREATED: 'ACKNOWLEDGED', ACKNOWLEDGED: 'ASSIGNED', ASSIGNED: 'DISPATCHED', DISPATCHED: 'RESOLVED' };

const COVERT_REASON = {
  DURESS_PIN: 'They entered their duress PIN, so their phone is now showing an ordinary screen.',
  COVERT_SOS: 'They sent a silent alert from a disguised screen on their phone.',
  SHAKE_SOS: 'They shook their phone to send a silent alert.',
};

function stepDetail(incident, status) {
  const at = {
    CREATED: incident.created_at,
    ACKNOWLEDGED: incident.acknowledged_at,
    ASSIGNED: incident.assigned_at,
    DISPATCHED: incident.dispatched_at,
    RESOLVED: incident.resolved_at,
  }[status];
  if (!at) return '';
  const who = status === 'ACKNOWLEDGED' ? incident.acknowledged_by : status === 'ASSIGNED' ? incident.assigned_to : '';
  return who ? `${clockTime(at)} · ${who}` : clockTime(at);
}

/** Title, facts, the do-not-contact warning for silent alerts, progress, and the next action. */
export default function IncidentSummary({ incident, canAct, onLifecycle, onOpenEvidence, nowMs }) {
  const next = NEXT_STATUS[incident.status];
  const reached = STATUS_ORDER.indexOf(incident.status);
  const priority = PRIORITY_CLASS[incident.priority] || 'check';
  const unregistered = String(incident.user_id || '').startsWith('unverified:');

  return (
    <section className="incident-head" aria-label="Incident summary">
      <div className="incident-title">
        <PriorityGlyph priority={incident.priority} size={26} />
        <h1>{label(TRIGGER_LABEL, incident.trigger_type)}</h1>
        <span className={`tag tag-${priority}`}>{label(PRIORITY_LABEL, incident.priority)}</span>
        {incident.category && incident.category !== 'PERSONAL_SAFETY' && (
          <span className="tag tag-covert">{label(CATEGORY_LABEL, incident.category)}</span>
        )}
      </div>

      <div className="incident-meta">
        <span>
          Raised {timeAgo(incident.created_at, nowMs)} ({clockTime(incident.created_at)})
        </span>
        <span>
          Near <span className="mono">{coords(incident.lat, incident.lng)}</span>
        </span>
        <span>
          Person <span className="mono">{shortId(incident.user_id)}</span>
          {unregistered ? ' (phone not registered)' : ''}
        </span>
        {Number(incident.impact_g_force) > 1.5 && <span>Impact {Number(incident.impact_g_force).toFixed(1)} g</span>}
        {!isCovert(incident) && (
          <span>
            Trusted contact{' '}
            {incident.trusted_contact_phone ? formatPhone(incident.trusted_contact_phone) : 'not set up'}
          </span>
        )}
      </div>

      {isCovert(incident) && (
        <div className="callout callout-danger" role="alert">
          <h2>Do not call or text this person</h2>
          <p>
            {COVERT_REASON[incident.trigger_type]} The person causing harm may be close by, and a call or
            message could put them in danger.
          </p>
          <ul>
            {GBV_SAFETY_PROTOCOLS.COVERT_DURESS.rules.map((rule) => (
              <li key={rule}>{rule}</li>
            ))}
          </ul>
          <p className="card-note">{GBV_SAFETY_PROTOCOLS.COVERT_DURESS.confirmationStatus}</p>
        </div>
      )}

      <ol className="steps" aria-label="Progress">
        {STATUS_ORDER.map((status, index) => {
          const done = index <= reached;
          const current = index === reached && status !== 'RESOLVED';
          return (
            <li key={status} className={`step${done ? ' is-done' : ''}${current ? ' is-current' : ''}`}>
              <span className="step-label">{STATUS_LABEL[status]}</span>
              <span className="step-meta">{stepDetail(incident, status) || (done ? '' : 'Not yet')}</span>
            </li>
          );
        })}
      </ol>

      <div className="incident-actions">
        {next ? (
          <button type="button" className="btn btn-primary" disabled={!canAct} onClick={() => onLifecycle(next)}>
            {NEXT_ACTION_LABEL[next]}
          </button>
        ) : (
          <span className="tag tag-ok">Resolved {clockTime(incident.resolved_at)}</span>
        )}
        <button type="button" className="btn" onClick={onOpenEvidence}>
          Evidence and activity log
        </button>
        {!canAct && next && <span className="faint">Only signed-in responders can update incidents.</span>}
      </div>
    </section>
  );
}
