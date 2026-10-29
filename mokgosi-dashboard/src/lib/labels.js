// Plain-language labels for the enum values the API returns, plus small formatting helpers.

export const PRIORITY_LABEL = { P1_CRITICAL: 'Critical', P2_HIGH: 'High', P3_VERIFY: 'Check' };
export const PRIORITY_CLASS = { P1_CRITICAL: 'critical', P2_HIGH: 'high', P3_VERIFY: 'check' };

export const STATUS_LABEL = {
  CREATED: 'New',
  ACKNOWLEDGED: 'Acknowledged',
  ASSIGNED: 'Assigned',
  DISPATCHED: 'Dispatched',
  RESOLVED: 'Resolved',
};
export const STATUS_ORDER = ['CREATED', 'ACKNOWLEDGED', 'ASSIGNED', 'DISPATCHED', 'RESOLVED'];

// Button label for moving an incident *into* each status.
export const NEXT_ACTION_LABEL = {
  ACKNOWLEDGED: 'Acknowledge',
  ASSIGNED: 'Assign',
  DISPATCHED: 'Mark as dispatched',
  RESOLVED: 'Resolve',
};

export const TRIGGER_LABEL = {
  EXPLICIT_SOS: 'SOS button',
  DURESS_PIN: 'Duress PIN',
  MISSED_CHECKIN: 'Missed check-in',
  MOTION_IMPACT: 'Possible fall or impact',
  COVERT_SOS: 'Silent alert',
  SHAKE_SOS: 'Shake alert',
};

export const CATEGORY_LABEL = {
  PERSONAL_SAFETY: 'Personal safety',
  GBV_DOMESTIC: 'Domestic violence',
  GBV_SEXUAL_VIOLENCE: 'Sexual violence',
  GBV_OTHER: 'Gender-based violence',
};

export const MEDIA_LABEL = {
  AUDIO_CONTEXT_CLIP: 'Audio clip',
  AUTHORIZED_CCTV_FRAME: 'Camera snapshot',
  SURVIVOR_AUDIO: 'Audio recording',
  SURVIVOR_PHOTO: 'Photo',
  SURVIVOR_NOTE: 'Written note',
};

export const AUDIT_LABEL = {
  INCIDENT_CREATED: 'Alert received',
  REPEAT_TRIGGER: 'Alert raised again',
  VIEW_INCIDENT: 'Opened the incident',
  OPEN_CCTV_STREAM: 'Opened a camera',
  VIEW_EVIDENCE: 'Opened the evidence',
  CCTV_SNAPSHOT_CAPTURED: 'Saved a camera snapshot',
  ACOUSTIC_CONTEXT_ATTACHED: 'Audio context added',
  LIFECYCLE_ACKNOWLEDGED: 'Acknowledged',
  LIFECYCLE_ASSIGNED: 'Assigned',
  LIFECYCLE_DISPATCHED: 'Marked as dispatched',
  LIFECYCLE_RESOLVED: 'Resolved',
  ESCALATION_NOTIFICATION_DISPATCHED: 'Trusted contact messaged',
  TRUSTED_CONTACT_ALERTED: 'Trusted contact messaged',
  TRUSTED_CONTACT_ACKNOWLEDGED: 'Trusted contact replied',
  TRUSTED_CONTACT_FAILED: 'Message to trusted contact failed',
  TRUSTED_CONTACT_DEMO_LOGGED: 'Trusted contact not messaged (demo)',
  TRUSTED_CONTACT_SKIPPED_NO_PROVIDER: 'Trusted contact not messaged: SMS not set up',
  TRUSTED_CONTACT_NOT_CONFIGURED: 'No trusted contact set up',
  INCIDENT_REFERRED_TO_PARTNER: 'Referred to a support organisation',
};

const SYSTEM_ACTORS = new Set(['MOKGOSI_INGEST_ENGINE', 'MOKGOSI_SAFE_NETWORK', 'MOKGOSI_TRUSTED_NOTIFIER']);

export function actorLabel(actorId) {
  if (!actorId) return '';
  if (SYSTEM_ACTORS.has(actorId)) return 'Mokgosi';
  if (String(actorId).startsWith('device:')) return 'Person’s phone';
  if (String(actorId).startsWith('contact:')) return 'Trusted contact';
  return actorId;
}

export const COVERT_TRIGGERS = new Set(['DURESS_PIN', 'COVERT_SOS', 'SHAKE_SOS']);

export function isCovert(incident) {
  return COVERT_TRIGGERS.has(incident?.trigger_type);
}

export function humanize(value) {
  if (!value) return '';
  const text = String(value).replace(/_/g, ' ').toLowerCase();
  return text.charAt(0).toUpperCase() + text.slice(1);
}

export function label(map, value) {
  return map[value] || humanize(value);
}

export function shortId(id) {
  return String(id || '').replace(/^unverified:/, '').slice(0, 8);
}

export function timeAgo(iso, nowMs = Date.now()) {
  if (!iso) return '';
  const seconds = Math.max(0, Math.round((nowMs - new Date(iso).getTime()) / 1000));
  if (seconds < 10) return 'just now';
  if (seconds < 60) return `${seconds} s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  const days = Math.floor(hours / 24);
  return days === 1 ? 'yesterday' : `${days} days ago`;
}

export function duration(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '0 s';
  if (seconds < 60) return `${Math.floor(seconds)} s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ${Math.floor(seconds % 60)} s`;
  return `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}

export function clockTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function dateTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

export function coords(lat, lng, digits = 4) {
  return `${Number(lat).toFixed(digits)}, ${Number(lng).toFixed(digits)}`;
}

// +26771234567 -> +267 71 234 567; other numbers are left as they are.
export function formatPhone(e164) {
  const match = /^\+267(\d{2})(\d{3})(\d{3})$/.exec(String(e164 || ''));
  return match ? `+267 ${match[1]} ${match[2]} ${match[3]}` : e164 || '';
}
