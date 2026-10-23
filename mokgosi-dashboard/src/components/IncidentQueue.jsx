import React, { useEffect, useState } from 'react';
import { SLA_ACK_THRESHOLD_SECONDS } from '../lib/api.js';

const PRIORITY_RANK = { P1_CRITICAL: 3, P2_HIGH: 2, P3_VERIFY: 1 };

export function sortIncidentsByUrgency(list) {
  return [...list].sort((a, b) => {
    const rankDiff = (PRIORITY_RANK[b.priority] || 0) - (PRIORITY_RANK[a.priority] || 0);
    if (rankDiff !== 0) return rankDiff;
    return new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
  });
}

function formatElapsed(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '0s';
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  const mins = Math.floor(seconds / 60);
  const rem = Math.floor(seconds % 60);
  return `${mins}m ${rem}s`;
}

/**
 * Priority-sorted incident queue with Active vs Resolved tabs, per-card live SLA
 * timer, silent duress warning badge, and GBV domestic category indicator.
 */
export default function IncidentQueue({
  incidents,
  selectedId,
  onSelect,
  activeTab,
  onTabChange,
}) {
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const activeList = sortIncidentsByUrgency(
    incidents.filter((inc) => inc.status !== 'RESOLVED'),
  );
  const resolvedList = sortIncidentsByUrgency(
    incidents.filter((inc) => inc.status === 'RESOLVED'),
  );
  const visible = activeTab === 'RESOLVED' ? resolvedList : activeList;

  return (
    <aside className="panel queue" aria-label="Incident Queue">
      <div className="queue-header">
        <h2>
          Incident Queue <small>{visible.length}</small>
        </h2>
        <div className="queue-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={activeTab !== 'RESOLVED'}
            className={`tab-btn ${activeTab !== 'RESOLVED' ? 'active' : ''}`}
            onClick={() => onTabChange('ACTIVE')}
          >
            Active ({activeList.length})
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === 'RESOLVED'}
            className={`tab-btn ${activeTab === 'RESOLVED' ? 'active' : ''}`}
            onClick={() => onTabChange('RESOLVED')}
          >
            Resolved ({resolvedList.length})
          </button>
        </div>
      </div>

      <div className="queue-list">
        {visible.length === 0 ? (
          <div className="empty-queue">
            {activeTab === 'RESOLVED'
              ? 'No resolved incidents in this session.'
              : 'No active incidents. Incoming SOS, Duress, and Check-In alerts appear here in < 1s.'}
          </div>
        ) : (
          visible.map((inc) => {
            const createdMs = new Date(inc.created_at || nowMs).getTime();
            const elapsedSeconds = Math.max(0, (nowMs - createdMs) / 1000);
            const unacknowledgedBreach =
              inc.status === 'CREATED' && elapsedSeconds >= SLA_ACK_THRESHOLD_SECONDS;
            const isDuress = inc.trigger_type === 'DURESS_PIN';
            const isGbv = inc.category === 'GBV_DOMESTIC';
            const priorityClass =
              inc.priority === 'P1_CRITICAL'
                ? 'p1'
                : inc.priority === 'P2_HIGH'
                ? 'p2'
                : 'p3';

            return (
              <button
                type="button"
                key={inc.id}
                className={`incident-card ${selectedId === inc.id ? 'selected' : ''} ${
                  isDuress ? 'duress-card' : ''
                }`}
                onClick={() => onSelect(inc)}
              >
                <div className="card-top-row">
                  <div className="badge-group">
                    <span className={`badge ${priorityClass}`}>{inc.priority}</span>
                    {isDuress && (
                      <span className="badge badge-duress">SILENT DURESS</span>
                    )}
                    {isGbv && (
                      <span className="badge badge-gbv">GBV / DOMESTIC</span>
                    )}
                  </div>
                  <span className="status-tag">{inc.status}</span>
                </div>

                <strong className="card-title">
                  {inc.trigger_type} · {inc.user_id}
                </strong>

                <div className="card-meta-row">
                  <small>
                    GPS {Number(inc.lat).toFixed(4)}, {Number(inc.lng).toFixed(4)} ·{' '}
                    {Number(inc.impact_g_force || 1).toFixed(1)}g
                  </small>
                  <span
                    className={`sla-timer ${unacknowledgedBreach ? 'breach' : ''}`}
                    title={
                      unacknowledgedBreach
                        ? `Unacknowledged beyond ${SLA_ACK_THRESHOLD_SECONDS}s SLA threshold`
                        : 'Elapsed time since incident creation'
                    }
                  >
                    SLA {formatElapsed(elapsedSeconds)}
                  </span>
                </div>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}

