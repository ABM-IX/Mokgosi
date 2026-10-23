import React, { useState } from 'react';

/**
 * Controlled Authorized CCTV Stream & Signed Snapshot Modal.
 * Embeds the opt-in camera feed (`<img>` MJPEG stream), handles stream
 * unavailability gracefully without blocking forensic snapshot signing,
 * and invokes `POST /api/v1/incidents/{id}/cctv-snapshot`.
 */
export default function CctvStreamModal({
  camera,
  incidentId,
  onClose,
  onCaptureSnapshot,
}) {
  const [streamError, setStreamError] = useState(false);
  const [capturing, setCapturing] = useState(false);
  const [captureResult, setCaptureResult] = useState(null);
  const [errorMsg, setErrorMsg] = useState('');

  if (!camera) return null;

  async function handleCapture() {
    setCapturing(true);
    setErrorMsg('');
    try {
      const res = await onCaptureSnapshot(camera.id);
      setCaptureResult(res);
    } catch (err) {
      setErrorMsg(err.message || 'Could not capture signed CCTV snapshot.');
    } finally {
      setCapturing(false);
    }
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Authorized CCTV Stream">
      <div className="modal-card">
        <div className="modal-header">
          <div>
            <h3>Authorized Opt-In CCTV · {camera.owner_name}</h3>
            <small>
              Distance: {Number(camera.distance_m || 0).toFixed(1)} m · Azimuth{' '}
              {camera.azimuth_deg}° · FOV {camera.fov_deg}° · Retention: 72h max
            </small>
          </div>
          <button type="button" className="btn-ghost" onClick={onClose}>
            ✕ Close
          </button>
        </div>

        <div className="stream-viewport">
          {!streamError ? (
            <img
              src={camera.stream_url}
              alt={`Authorized feed from ${camera.owner_name}`}
              onError={() => setStreamError(true)}
            />
          ) : (
            <div className="stream-fallback">
              <strong>Stream unavailable — signed snapshot still available</strong>
              <p>
                Live feed at <code>{camera.stream_url}</code> is not currently streaming. In{' '}
                <code>DEMO_MODE</code>, capturing a snapshot signs a deterministic{' '}
                <code>AUTHORIZED_CCTV_FRAME</code> forensic manifest.
              </p>
            </div>
          )}
        </div>

        {errorMsg && <div className="notice">{errorMsg}</div>}

        {captureResult?.manifest && (
          <div className="snapshot-confirmation">
            <b>✓ Signed CCTV Snapshot Sealed in Evidence Vault</b>
            <code>SHA-256: {captureResult.manifest.media_sha256}</code>
            <code>Ed25519: {captureResult.manifest.ed25519_signature}</code>
            <small>
              Key ID: {captureResult.manifest.public_key_id} · Provenance:{' '}
              {captureResult.manifest.location_provenance}
            </small>
          </div>
        )}

        <div className="modal-actions">
          <span className="audit-note">
            Audit logged: <code>OPEN_CCTV_STREAM</code> (Incident #{String(incidentId).slice(0, 8)})
          </span>
          <div className="actions">
            <button type="button" onClick={handleCapture} disabled={capturing}>
              {capturing ? 'Signing Frame…' : 'Capture Signed Snapshot (Ed25519)'}
            </button>
            <button type="button" className="muted" onClick={onClose}>
              Done
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

