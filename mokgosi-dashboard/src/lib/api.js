export const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000';
// A plain comparison so the bundler can drop demo-only code and sample data from production builds.
export const DEMO_MODE = import.meta.env.VITE_DEMO_MODE === 'true';
export const DEFAULT_DEMO_TOKEN = import.meta.env.VITE_DEMO_RESPONDER_TOKEN || '';
export const SLA_ACK_THRESHOLD_SECONDS = Number(import.meta.env.VITE_SLA_ACK_THRESHOLD_SECONDS || 60);

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

export async function fetchHotspots() {
  const res = await fetch(`${API_BASE}/api/v1/analytics/hotspots`);
  if (!res.ok) {
    throw new Error(`Hotspots fetch failed (${res.status})`);
  }
  return res.json();
}

export async function fetchIncidentReferrals(incidentId, accessToken) {
  if (!incidentId || !accessToken) return { referrals: [] };
  try {
    const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/referrals`, {
      headers: authHeaders(accessToken),
    });
    return res.ok ? res.json() : { referrals: [] };
  } catch {
    return { referrals: [] };
  }
}

export async function postIncidentReferral(incidentId, partnerId, notes, accessToken) {
  const res = await fetch(`${API_BASE}/api/v1/incidents/${incidentId}/referrals`, {
    method: 'POST',
    headers: authHeaders(accessToken, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ partner_id: partnerId, notes }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Referral failed (${res.status}): ${detail}`);
  }
  return res.json();
}

export async function fetchSurvivorConsents(userId, accessToken) {
  if (!userId) return null;
  try {
    const res = await fetch(`${API_BASE}/api/v1/consents/${userId}`, {
      headers: authHeaders(accessToken, { 'X-Device-Key': 'DEMO_DEVICE_KEY' }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data.consents || null;
  } catch {
    return null;
  }
}


