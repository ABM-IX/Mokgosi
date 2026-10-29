import React from 'react';
import Icon from './Icons.jsx';
import { TRIGGER_LABEL, isCovert, label, timeAgo } from '../lib/labels.js';

/** Critical alerts nobody has picked up yet. Stays until the last one is acknowledged, so it cannot be missed. */
export default function AlertBanner({ incidents, onOpen, nowMs }) {
  const waiting = incidents
    .filter((inc) => inc.priority === 'P1_CRITICAL' && inc.status === 'CREATED')
    .sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
  if (waiting.length === 0) return null;
  const newest = waiting[0];
  const silent = isCovert(newest);

  return (
    <div className="alert-banner" role="alert" aria-live="assertive">
      <span className="alert-banner-dot" aria-hidden="true" />
      <div className="alert-banner-text">
        <strong>
          {waiting.length === 1 ? '1 critical alert' : `${waiting.length} critical alerts`} not yet acknowledged
        </strong>
        <span>
          Newest: {label(TRIGGER_LABEL, newest.trigger_type)}, {timeAgo(newest.created_at, nowMs)}
          {silent ? '. Silent alert: do not call or text this person.' : ''}
        </span>
      </div>
      <button type="button" className="btn btn-small btn-danger" onClick={() => onOpen(newest)}>
        Open <Icon name="arrowRight" size={14} />
      </button>
    </div>
  );
}
