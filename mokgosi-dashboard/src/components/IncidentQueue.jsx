import React, { useEffect, useState } from 'react';
import { SLA_ACK_THRESHOLD_SECONDS } from '../lib/api.js';
import {
  CATEGORY_LABEL,
  PRIORITY_CLASS,
  PRIORITY_LABEL,
  STATUS_LABEL,
  TRIGGER_LABEL,
  duration,
  isCovert,
  label,
  shortId,
  timeAgo,
} from '../lib/labels.js';

const PRIORITY_RANK = { P1_CRITICAL: 3, P2_HIGH: 2, P3_VERIFY: 1 };

export function sortIncidentsByUrgency(list) {
  return [...list].sort((a, b) => {
    const rankDiff = (PRIORITY_RANK[b.priority] || 0) - (PRIORITY_RANK[a.priority] || 0);
    if (rankDiff !== 0) return rankDiff;
    return new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
  });
}

export function isGbvIncident(inc) {
  if (!inc) return false;
  const cat = inc.category || '';
  return (
    cat.startsWith('GBV_') ||
    inc.trigger_type === 'COVERT_SOS' ||
    inc.trigger_type === 'DURESS_PIN'
  );
}

/** Open / resolved incident list for the current incident type, most urgent first. */
export default function IncidentQueue({
  incidents,
  selectedId,
  onSelect,
  activeTab,
  onTabChange,
  activePillar = 'SAFER_COMMUNITIES',
}) {
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const pillarFiltered = incidents.filter((inc) => {
    if (!activePillar) return true;
    const gbv = isGbvIncident(inc);
    return activePillar === 'GBV_RESPONSE' ? gbv : !gbv;
  });

  const activeList = sortIncidentsByUrgency(pillarFiltered.filter((inc) => inc.status !== 'RESOLVED'));
  const resolvedList = sortIncidentsByUrgency(pillarFiltered.filter((inc) => inc.status === 'RESOLVED'));
  const showResolved = activeTab === 'RESOLVED';
  const visible = showResolved ? resolvedList : activeList;

  return (
    <aside className="queue" aria-label="Incidents">
      <div className="queue-head">
        <div className="tabs" role="tablist" aria-label="Incident list">
          <button type="button" role="tab" aria-selected={!showResolved} onClick={() => onTabChange('ACTIVE')}>
            Open <span className="count">{activeList.length}</span>
          </button>
          <button type="button" role="tab" aria-selected={showResolved} onClick={() => onTabChange('RESOLVED')}>
            Resolved <span className="count">{resolvedList.length}</span>
          </button>
        </div>
      </div>

      <ul className="queue-list">
        {visible.length === 0 ? (
          <li className="queue-empty">
            {showResolved ? 'Nothing resolved yet.' : 'No open incidents. New alerts appear here as they arrive.'}
          </li>
        ) : (
          visible.map((inc) => {
            const elapsedSeconds = Math.max(0, (nowMs - new Date(inc.created_at || nowMs).getTime()) / 1000);
            const unacknowledged = inc.status === 'CREATED' && elapsedSeconds >= SLA_ACK_THRESHOLD_SECONDS;
            const priority = PRIORITY_CLASS[inc.priority] || 'check';
            const gbvCategory = inc.category && inc.category.startsWith('GBV_');
            return (
              <li key={inc.id}>
                <button
                  type="button"
                  className={`queue-item prio-${priority} ${selectedId === inc.id ? 'is-selected' : ''}`}
                  aria-current={selectedId === inc.id ? 'true' : undefined}
                  onClick={() => onSelect(inc)}
                >
                  <span className="queue-item-top">
                    <span className="queue-title">{label(TRIGGER_LABEL, inc.trigger_type)}</span>
                    <span className="queue-age">{timeAgo(inc.created_at, nowMs)}</span>
                  </span>
                  <span className="queue-meta">
                    <span className={`tag tag-${priority}`}>{label(PRIORITY_LABEL, inc.priority)}</span>
                    <span>{label(STATUS_LABEL, inc.status)}</span>
                    <span>·</span>
                    <span className="mono">{shortId(inc.user_id)}</span>
                  </span>
                  {(isCovert(inc) || gbvCategory) && (
                    <span className="queue-meta">
                      {isCovert(inc) && <span className="tag tag-covert">Do not contact</span>}
                      {gbvCategory && <span>{label(CATEGORY_LABEL, inc.category)}</span>}
                    </span>
                  )}
                  {unacknowledged && (
                    <span className="queue-breach">Not acknowledged for {duration(elapsedSeconds)}</span>
                  )}
                </button>
              </li>
            );
          })
        )}
      </ul>
    </aside>
  );
}
