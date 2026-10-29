import React, { useState } from 'react';
import { DEMO_MODE } from '../lib/api.js';

/**
 * Live view of one opt-in camera near an incident, with a signed snapshot. The server only signs a
 * frame from a camera within 150 m of the incident; opening this is written to the activity log.
 */
export default function CctvStreamModal({ camera, onClose, onCaptureSnapshot }) {
  const [streamError, setStreamError] = useState(false);
  const [capturing, setCapturing] = useState(false);
  const [result, setResult] = useState(null);
  const [errorMsg, setErrorMsg] = useState('');

  if (!camera) return null;

  async function handleCapture() {
    setCapturing(true);
    setErrorMsg('');
    try {
      setResult(await onCaptureSnapshot(camera.id));
    } catch (err) {
      setErrorMsg(err.message || 'The snapshot could not be saved.');
    } finally {
      setCapturing(false);
    }
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label={`Camera: ${camera.owner_name}`}>
      <div className="modal">
        <div className="modal-head">
          <div>
            <h2>{camera.owner_name}</h2>
            <p className="card-note">
              {Number(camera.distance_m || 0).toFixed(0)} m from the incident · facing {camera.azimuth_deg}° · footage kept
              for 72 hours
            </p>
          </div>
          <button type="button" className="btn btn-quiet btn-small" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="camera-view">
          {!streamError ? (
            <img src={camera.stream_url} alt={`Live view from ${camera.owner_name}`} onError={() => setStreamError(true)} />
          ) : (
            <p>
              No live picture from this camera right now.
              {DEMO_MODE ? ' In demo mode, a placeholder frame is signed when you save a snapshot.' : ''}
            </p>
          )}
        </div>

        {errorMsg && (
          <p className="verify-result is-bad" role="alert">
            {errorMsg}
          </p>
        )}
        {result?.manifest && (
          <p className="verify-result is-ok" role="status">
            Snapshot saved and signed. Fingerprint <span className="mono">{String(result.manifest.media_sha256).slice(0, 16)}…</span>
          </p>
        )}

        <div className="modal-foot">
          <span className="card-note">Opening a camera is recorded in the activity log.</span>
          <div className="row">
            <button type="button" className="btn" onClick={onClose}>
              Done
            </button>
            <button type="button" className="btn btn-primary" disabled={capturing} onClick={handleCapture}>
              {capturing ? 'Saving…' : 'Save signed snapshot'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
