import React, { useState } from 'react';
import { verifyEvidenceManifest } from '../lib/api.js';

/**
 * Cryptographic Evidence Docket & Append-Only Audit Trail Modal/Panel.
 * Displays full SHA-256 digests, Ed25519 signatures, public key IDs, capture vs
 * server-receipt timestamps, and live signature verification (`✓` valid vs `✗` tampered).
 */
export default function EvidenceDocketModal({
  manifests = [],
  logs = [],
  isModal = false,
  onClose,
}) {
  const [verificationStates, setVerificationStates] = useState({});

  async function handleVerify(manifest, tamper = false) {
    const key = `${manifest.id}-${tamper ? 'tamper' : 'real'}`;
    setVerificationStates((prev) => ({
      ...prev,
      [manifest.id]: { loading: true, mode: tamper ? 'TAMPER_TEST' : 'AUTHENTIC' },
    }));
    try {
      const payloadToVerify = JSON.parse(JSON.stringify(manifest));
      if (tamper && payloadToVerify.manifest_payload) {
        const orig = String(payloadToVerify.manifest_payload.media_sha256 || '');
        payloadToVerify.manifest_payload.media_sha256 =
          (orig.startsWith('0') ? 'f' : '0') + orig.slice(1);
      }
      const res = await verifyEvidenceManifest(payloadToVerify);
      setVerificationStates((prev) => ({
        ...prev,
        [manifest.id]: {
          loading: false,
          valid: Boolean(res.valid),
          tamperTested: tamper,
          key,
        },
      }));
    } catch (err) {
      setVerificationStates((prev) => ({
        ...prev,
        [manifest.id]: {
          loading: false,
          valid: false,
          error: err.message,
          tamperTested: tamper,
        },
      }));
    }
  }

  const content = (
    <>
      <div className="panel-title-row">
        <h3>Cryptographic Evidence Docket (SHA-256 + Ed25519) &amp; Audit Trail</h3>
        {isModal && onClose && (
          <button type="button" className="btn-ghost" onClick={onClose}>
            ✕ Close
          </button>
        )}
      </div>

      {manifests.length === 0 ? (
        <p className="muted-copy">
          No signed media manifests attached yet. Capture a CCTV snapshot or attach acoustic
          context to generate an Ed25519-signed manifest.
        </p>
      ) : (
        manifests.map((m) => {
          const vState = verificationStates[m.id];
          return (
            <div className="evidence-card" key={m.id}>
              <div className="evidence-header">
                <b>{m.media_type}</b>
                <span className="key-badge">Key: {m.public_key_id}</span>
              </div>

              <div className="hash-row">
                <span>SHA-256 Digest:</span>
                <code>{m.media_sha256}</code>
              </div>
              <div className="hash-row">
                <span>Ed25519 Signature:</span>
                <code>{m.ed25519_signature}</code>
              </div>

              <div className="timestamp-row">
                <small>
                  Source Capture UTC: <b>{m.source_capture_utc || 'N/A'}</b>
                </small>
                <small>
                  Server Receipt UTC: <b>{m.server_receipt_utc || 'N/A'}</b>
                </small>
                <small>
                  Provenance: <b>{m.location_provenance}</b>
                </small>
              </div>

              <div className="verify-bar">
                <div className="actions">
                  <button
                    type="button"
                    onClick={() => handleVerify(m, false)}
                    disabled={vState?.loading}
                  >
                    Verify Signature (Ed25519)
                  </button>
                  <button
                    type="button"
                    className="muted"
                    onClick={() => handleVerify(m, true)}
                    disabled={vState?.loading}
                    title="Flips 1 hex nibble of media_sha256 before calling /api/v1/evidence/verify"
                  >
                    Simulate 1-Byte Tamper Test
                  </button>
                </div>

                {vState && !vState.loading && (
                  <span
                    className={`verify-badge ${vState.valid ? 'valid' : 'invalid'}`}
                    role="status"
                  >
                    {vState.valid
                      ? '✓ VALID — Canonical JSON & Ed25519 Signature Verified'
                      : vState.tamperTested
                      ? '✗ INVALID — Tampered Payload Rejected by Ed25519 Verifier'
                      : '✗ INVALID SIGNATURE'}
                  </span>
                )}
              </div>
            </div>
          );
        })
      )}

      <div className="audit-section">
        <h4>Append-Only Audit Trail ({logs.length} events)</h4>
        {logs.length === 0 ? (
          <small className="muted-copy">No audit entries recorded yet.</small>
        ) : (
          logs.map((l) => (
            <div className="log-row" key={l.id}>
              <time>{new Date(l.timestamp_utc).toLocaleTimeString()}</time>
              <b>{l.actor_id}</b> · <span className="log-action">{l.action}</span>
            </div>
          ))
        )}
      </div>
    </>
  );

  if (isModal) {
    return (
      <div className="modal-backdrop" role="dialog" aria-modal="true">
        <div className="modal-card">{content}</div>
      </div>
    );
  }

  return <div className="panel">{content}</div>;
}

