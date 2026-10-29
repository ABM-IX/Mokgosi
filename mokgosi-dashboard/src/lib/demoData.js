/**
 * Sample data for demo mode only (VITE_DEMO_MODE=true with no Supabase connection).
 * Places are real Gaborone locations; people and incidents are invented. The data that needs the clock
 * is built in pure-annotated calls so production builds drop it.
 */

const now = Date.now();
const ago = (ms) => new Date(now - ms).toISOString();

export const DEMO_CAMERAS = [
  {
    id: 'cam-cbd-04',
    owner_name: 'Gaborone CBD, pole 4',
    lat: -24.6545,
    lng: 25.9085,
    azimuth_deg: 180,
    fov_deg: 110,
    is_authorized: true,
    connection_status: 'ONLINE',
    stream_url: 'http://localhost:8080/video',
    distance_m: 35.4,
  },
  {
    id: 'cam-mall-02',
    owner_name: 'Main Mall, shop camera 2',
    lat: -24.658,
    lng: 25.912,
    azimuth_deg: 90,
    fov_deg: 95,
    is_authorized: true,
    connection_status: 'ONLINE',
    stream_url: 'http://localhost:8080/video',
    distance_m: 68.2,
  },
  {
    id: 'cam-ub-07',
    owner_name: 'UB north gate',
    lat: -24.6605,
    lng: 25.9315,
    azimuth_deg: 240,
    fov_deg: 100,
    is_authorized: true,
    connection_status: 'ONLINE',
    stream_url: 'http://localhost:8080/video',
    distance_m: 52.0,
  },
  {
    id: 'cam-station-12',
    owner_name: 'Station interchange, camera 12',
    lat: -24.6588,
    lng: 25.9035,
    azimuth_deg: 45,
    fov_deg: 90,
    is_authorized: true,
    connection_status: 'ONLINE',
    stream_url: 'http://localhost:8080/video',
    distance_m: 82.1,
  },
  {
    id: 'cam-broadhurst-01',
    owner_name: 'Broadhurst community hub',
    lat: -24.6325,
    lng: 25.9215,
    azimuth_deg: 135,
    fov_deg: 105,
    is_authorized: true,
    connection_status: 'ONLINE',
    stream_url: 'http://localhost:8080/video',
    distance_m: 112.5,
  },
];

const NO_AUDIO = { status: 'AWAITING_OR_BYPASSED', tags: [], confidence: null };

function incident(fields) {
  return {
    trusted_contact_phone: null,
    category: 'PERSONAL_SAFETY',
    impact_g_force: 1.0,
    ai_context: NO_AUDIO,
    acknowledged_by: null,
    acknowledged_at: null,
    assigned_to: null,
    assigned_at: null,
    dispatched_at: null,
    resolved_at: null,
    client_event_id: null,
    ...fields,
    source_capture_utc: fields.created_at,
  };
}

export const DEMO_INCIDENTS = /* @__PURE__ */ (() => [
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000001',
    user_id: 'b7e3c2a1-4d5f-4a8b-9c1e-2f3a4b5c6d71',
    trusted_contact_phone: '+26771234567',
    trigger_type: 'EXPLICIT_SOS',
    priority: 'P1_CRITICAL',
    status: 'CREATED',
    lat: -24.6548,
    lng: 25.9088,
    ai_context: {
      status: 'ANALYZED',
      model: 'DETERMINISTIC_DEMO',
      tags: ['Demo distress profile', 'Screaming (0.91)', 'Groan / Struggle (0.78)'],
      confidence: 0.91,
    },
    created_at: ago(45000),
  }),
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000002',
    user_id: '5f0a9c3e-8b2d-4e61-a7f4-1c9d2e3b4a85',
    trusted_contact_phone: '+26772345678',
    trigger_type: 'DURESS_PIN',
    category: 'GBV_DOMESTIC',
    priority: 'P1_CRITICAL',
    status: 'ACKNOWLEDGED',
    lat: -24.632,
    lng: 25.921,
    acknowledged_by: 'DISP_GABORONE_01',
    acknowledged_at: ago(80000),
    created_at: ago(120000),
  }),
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000003',
    user_id: '2c8e4f6a-1b3d-4c5e-9f7a-8d6b4e2c0a19',
    trusted_contact_phone: '+26773456789',
    trigger_type: 'MOTION_IMPACT',
    priority: 'P2_HIGH',
    status: 'ASSIGNED',
    lat: -24.6582,
    lng: 25.9124,
    impact_g_force: 3.9,
    acknowledged_by: 'DISP_GABORONE_01',
    acknowledged_at: ago(300000),
    assigned_to: 'Patrol, Main Mall',
    assigned_at: ago(240000),
    created_at: ago(360000),
  }),
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000004',
    user_id: '9a1c3e5f-7b9d-4f2a-8c4e-6a8c0e2f4b63',
    trusted_contact_phone: '+26774567890',
    trigger_type: 'MISSED_CHECKIN',
    priority: 'P3_VERIFY',
    status: 'CREATED',
    lat: -24.6612,
    lng: 25.9322,
    created_at: ago(500000),
  }),
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000005',
    user_id: 'e4f6a8c0-2d4f-4b6d-8f0a-2c4e6a8c0d27',
    trigger_type: 'SHAKE_SOS',
    priority: 'P1_CRITICAL',
    status: 'DISPATCHED',
    lat: -24.6592,
    lng: 25.9038,
    impact_g_force: 2.1,
    acknowledged_by: 'DISP_GABORONE_01',
    acknowledged_at: ago(700000),
    assigned_to: 'Patrol, station',
    assigned_at: ago(640000),
    dispatched_at: ago(580000),
    created_at: ago(750000),
  }),
  incident({
    id: 'a1b2c3d4-e5f6-4a1b-8c2d-000000000006',
    user_id: '5f0a9c3e-8b2d-4e61-a7f4-1c9d2e3b4a85',
    trusted_contact_phone: '+26772345678',
    trigger_type: 'COVERT_SOS',
    category: 'GBV_DOMESTIC',
    priority: 'P1_CRITICAL',
    status: 'RESOLVED',
    lat: -24.6321,
    lng: 25.9208,
    acknowledged_by: 'DISP_GABORONE_02',
    acknowledged_at: ago(3 * 86400000 - 60000),
    assigned_to: 'Social worker, Broadhurst',
    assigned_at: ago(3 * 86400000 - 300000),
    dispatched_at: ago(3 * 86400000 - 600000),
    resolved_at: ago(3 * 86400000 - 7200000),
    created_at: ago(3 * 86400000),
  }),
])();

export const DEMO_BREADCRUMBS = /* @__PURE__ */ (() => ({
  'a1b2c3d4-e5f6-4a1b-8c2d-000000000001': [
    { lat: -24.6542, lng: 25.908, captured_at_utc: ago(75000) },
    { lat: -24.6545, lng: 25.9084, captured_at_utc: ago(60000) },
    { lat: -24.6548, lng: 25.9088, captured_at_utc: ago(45000) },
  ],
  'a1b2c3d4-e5f6-4a1b-8c2d-000000000003': [
    { lat: -24.6575, lng: 25.911, captured_at_utc: ago(400000) },
    { lat: -24.658, lng: 25.9118, captured_at_utc: ago(380000) },
    { lat: -24.6582, lng: 25.9124, captured_at_utc: ago(360000) },
  ],
}))();

const log = (id, action, actor_id, msAgo, client_metadata = {}) => ({
  id,
  action,
  actor_id,
  timestamp_utc: ago(msAgo),
  client_metadata,
});

export const DEMO_LOGS = /* @__PURE__ */ (() => ({
  'a1b2c3d4-e5f6-4a1b-8c2d-000000000001': [
    log('d1-1', 'INCIDENT_CREATED', 'MOKGOSI_INGEST_ENGINE', 45000),
    log('d1-2', 'TRUSTED_CONTACT_SKIPPED_NO_PROVIDER', 'MOKGOSI_TRUSTED_NOTIFIER', 44000),
  ],
  'a1b2c3d4-e5f6-4a1b-8c2d-000000000002': [
    log('d2-1', 'INCIDENT_CREATED', 'MOKGOSI_INGEST_ENGINE', 120000),
    log('d2-2', 'ESCALATION_NOTIFICATION_DISPATCHED', 'MOKGOSI_SAFE_NETWORK', 118000, { priority: 1 }),
    log('d2-3', 'LIFECYCLE_ACKNOWLEDGED', 'DISP_GABORONE_01', 80000),
    log('d2-4', 'TRUSTED_CONTACT_ACKNOWLEDGED', 'trusted contact 1', 70000),
  ],
}))();

export const DEMO_HOTSPOTS = {
  hotspots: [
    { grid_lat: -24.655, grid_lng: 25.91, cell_size_meters: 500, category: 'PERSONAL_SAFETY', incident_count: 23, density_level: 'HIGH' },
    { grid_lat: -24.66, grid_lng: 25.905, cell_size_meters: 500, category: 'PERSONAL_SAFETY', incident_count: 12, density_level: 'MEDIUM' },
    { grid_lat: -24.63, grid_lng: 25.92, cell_size_meters: 500, category: 'GBV_DOMESTIC', incident_count: 11, density_level: 'MEDIUM' },
    { grid_lat: -24.66, grid_lng: 25.93, cell_size_meters: 500, category: 'PERSONAL_SAFETY', incident_count: 6, density_level: 'LOW' },
  ],
};
