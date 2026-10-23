export const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000';
export const DEMO_MODE = String(import.meta.env.VITE_DEMO_MODE || 'false').toLowerCase() === 'true';
export const DEFAULT_DEMO_TOKEN = import.meta.env.VITE_DEMO_RESPONDER_TOKEN || '';
export const SLA_ACK_THRESHOLD_SECONDS = Number(import.meta.env.VITE_SLA_ACK_THRESHOLD_SECONDS || 60);

/**
 * Configurable GBV & Personal Safety Responder Referral Directory.
 * Per project rules, no phone numbers or partner endorsements are invented;
 * entries remain clearly marked TODO until confirmed with official partners.
 */
export const RESPONDER_REFERRAL_RESOURCES = [
  {
    id: 'bps-gbv',
    name: 'Botswana Police Service — Gender & Child Protection Branch',
    contact: 'TODO: confirm with Botswana Police Service GBV desk',
    notes: 'Verify survivor safety and covert duress state before any external dispatch.',
  },
  {
    id: 'gender-affairs',
    name: 'Department of Gender Affairs — Crisis Support Referral',
    contact: 'TODO: confirm with Department of Gender Affairs',
    notes: 'Coordinate shelter & social-worker intake upon survivor request.',
  },
  {
    id: 'ngo-shelter',
    name: 'Accredited GBV Shelter & Legal Aid Partners',
    contact: 'TODO: confirm with NGO partners',
    notes: 'Provide signed Ed25519 evidence manifest only with explicit survivor consent.',
  },
];

function authHeaders(accessToken, extra = {}) {
  const headers = { ...extra };
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }
  return headers;
}

export async function patchIncidentLifecycle(incidentId, newStatus, accessToken) {
  const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/lifecycle`, {
    method: 'PATCH',
    headers: authHeaders(accessToken, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ new_status: newStatus }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Lifecycle update failed (${res.status}): ${detail}`);
  }
  return res.json();
}

export async function postAcousticSimulation(incidentId, profile, accessToken) {
  const form = new FormData();
  form.append('simulated_profile', profile);
  const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/acoustic-context`, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: form,
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Acoustic context request failed (${res.status}): ${detail}`);
  }
  return res.json();
}

export async function postCctvSnapshot(incidentId, cameraId, accessToken) {
  const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/cctv-snapshot`, {
    method: 'POST',
    headers: authHeaders(accessToken, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ camera_id: cameraId }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`CCTV snapshot failed (${res.status}): ${detail}`);
  }
  return res.json();
}

export async function postIncidentAudit(incidentId, action, accessToken) {
  if (!incidentId || !accessToken) return null;
  try {
    const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/audit`, {
      method: 'POST',
      headers: authHeaders(accessToken, { 'Content-Type': 'application/json' }),
      body: JSON.stringify({ action }),
    });
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

export async function verifyEvidenceManifest(manifestPayload) {
  const res = await fetch(`${API_BASE}/api/v1/evidence/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(manifestPayload),
  });
  if (!res.ok) {
    throw new Error(`Verification request failed (${res.status})`);
  }
  return res.json();
}

