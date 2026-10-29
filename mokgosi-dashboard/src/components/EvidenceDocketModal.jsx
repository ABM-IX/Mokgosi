import React, { useState } from 'react';
import { verifyEvidenceManifest } from '../lib/api.js';
import { AUDIT_LABEL, MEDIA_LABEL, actorLabel, clockTime, dateTime, humanize, label } from '../lib/labels.js';

function resultText(state) {
  if (state.error) return 'Could not reach the server to check this record.';
  if (state.tamperTested) {
    return state.valid
      ? 'The changed copy was accepted. Report this: it should have been rejected.'
      : 'The changed copy was rejected, as it should be.';
  }
  if (state.valid) {
    return state.keyStatus === 'retired'
      ? 'Signature valid (signed with an earlier Mokgosi key). This record has not changed since it was received.'
      : 'Signature valid. This record has not changed since it was received.';
  }
  return state.reason === 'KEY_COMPROMISED'
    ? 'Signed with a key that is no longer trusted. Do not rely on this record.'
    : 'Signature does not match. This record was changed, or was not signed by Mokgosi.';
}

/** Signed records (hash + Ed25519 signature) attached to an incident, and its append-only activity log. */
export default function EvidenceDocketModal({ manifests = [], logs = [], isModal = false, onClose }) {
  const [checks, setChecks] = useState({});

  async function check(manifest, tamper) {
    setChecks((prev) => ({ ...prev, [manifest.id]: { loading: true } }));
    const copy = JSON.parse(JSON.stringify(manifest));
    if (tamper && copy.manifest_payload) {
      const digest = String(copy.manifest_payload.media_sha256 || '');
      copy.manifest_payload.media_sha256 = (digest.startsWith('0') ? 'f' : '0') + digest.slice(1);
    }
    try {
      const res = await verifyEvidenceManifest(copy);
      setChecks((prev) => ({
        ...prev,
        [manifest.id]: { valid: Boolean(res.valid), reason: res.reason, keyStatus: res.key_status, tamperTested: tamper },
      }));
    } catch {
      setChecks((prev) => ({ ...prev, [manifest.id]: { error: true } }));
    }
  }

  const content = (
    <>
      <div className="modal-head">
        <div>
          <h2>Evidence and activity log</h2>
          <p className="card-note">Each record is fingerprinted (SHA-256) and signed (Ed25519) when the server receives it.</p>
        </div>
        {isModal && onClose && (
          <button type="button" className="btn btn-quiet btn-small" onClick={onClose}>
            Close
          </button>
        )}
      </div>

      <section className="card" aria-label="Signed records">
        <h3>Signed records</h3>
        {manifests.length === 0 ? (
          <p className="muted">No records yet. Camera snapshots and audio clips appear here once they are saved.</p>
        ) : (
          <div>
            {manifests.map((m) => {
              const state = checks[m.id];
              return (
                <div className="record" key={m.id || m.ed25519_signature}>
                  <div className="record-head">
                    <strong>{label(MEDIA_LABEL, m.media_type)}</strong>
                    <span className="faint">Received {dateTime(m.server_receipt_utc)}</span>
                  </div>
                  <dl className="facts">
                    <dt>Captured</dt>
                    <dd>{m.source_capture_utc ? dateTime(m.source_capture_utc) : 'Not recorded'}</dd>
                    <dt>Source</dt>
                    <dd>{m.location_provenance}</dd>
                    <dt>Fingerprint</dt>
                    <dd className="mono" title={m.media_sha256}>
                      {String(m.media_sha256 || '').slice(0, 16)}…
                    </dd>
                    <dt>Signing key</dt>
                    <dd className="mono">{m.public_key_id}</dd>
                  </dl>
                  <div className="row">
                    <button type="button" className="btn btn-small" disabled={state?.loading} onClick={() => check(m, false)}>
                      Check signature
                    </button>
                    <button
                      type="button"
                      className="btn btn-small btn-quiet"
                      disabled={state?.loading}
                      title="Changes one character of the fingerprint, then asks the server to check it"
                      onClick={() => check(m, true)}
                    >
                      Test with a changed copy
                    </button>
                    {state && !state.loading && (
                      <span
                        className={`verify-result ${state.valid !== state.tamperTested && !state.error ? 'is-ok' : 'is-bad'}`}
                        role="status"
                      >
                        {resultText(state)}
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <section className="card" aria-label="Activity log">
        <div className="card-head">
          <h3>Activity log</h3>
          <span className="card-note">Entries cannot be edited or deleted.</span>
        </div>
        {logs.length === 0 ? (
          <p className="muted">Nothing recorded yet.</p>
        ) : (
          <table className="table">
            <tbody>
              {logs.map((log) => (
                <tr key={log.id}>
                  <td className="num faint">{clockTime(log.timestamp_utc)}</td>
                  <td>{AUDIT_LABEL[log.action] || humanize(log.action)}</td>
                  <td className="muted">{actorLabel(log.actor_id)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </>
  );

  if (!isModal) return content;
  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Evidence and activity log">
      <div className="modal">{content}</div>
    </div>
  );
}
