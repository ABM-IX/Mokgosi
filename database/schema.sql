-- MOKGOSI Master Schema (v3.0 - Two-Pillar: Safer Communities & GBV Response)
-- Safe to re-run against a Supabase / PostgreSQL project with PostGIS.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enums & Taxonomies
DO $$ BEGIN CREATE TYPE incident_priority AS ENUM ('P1_CRITICAL','P2_HIGH','P3_VERIFY');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE incident_status AS ENUM ('CREATED','ACKNOWLEDGED','ASSIGNED','DISPATCHED','RESOLVED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE trigger_source AS ENUM ('EXPLICIT_SOS','DURESS_PIN','MISSED_CHECKIN','MOTION_IMPACT','COVERT_SOS','SHAKE_SOS');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- If trigger_source enum already exists without the new covert values, add them safely
DO $$ BEGIN ALTER TYPE trigger_source ADD VALUE IF NOT EXISTS 'COVERT_SOS'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TYPE trigger_source ADD VALUE IF NOT EXISTS 'SHAKE_SOS'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 1. Registered Cameras (Pillar A - Public CCTV Mesh)
CREATE TABLE IF NOT EXISTS registered_cameras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_name TEXT NOT NULL,
  location GEOGRAPHY(POINT,4326) NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  azimuth_deg INT CHECK (azimuth_deg BETWEEN 0 AND 360),
  fov_deg INT DEFAULT 90,
  is_authorized BOOLEAN DEFAULT TRUE,
  connection_status TEXT DEFAULT 'ONLINE',
  stream_url TEXT NOT NULL,
  retention_policy_hours INT DEFAULT 72,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Incidents (Shared Core Engine: Pillar A & Pillar B)
CREATE TABLE IF NOT EXISTS incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  trusted_contact_phone TEXT,
  trigger_type trigger_source NOT NULL,
  category TEXT NOT NULL DEFAULT 'PERSONAL_SAFETY' CHECK (category IN ('PERSONAL_SAFETY','GBV_DOMESTIC','GBV_SEXUAL_VIOLENCE','GBV_OTHER')),
  priority incident_priority NOT NULL,
  status incident_status DEFAULT 'CREATED',
  location GEOGRAPHY(POINT,4326) NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  impact_g_force DOUBLE PRECISION DEFAULT 1.0,
  ai_context JSONB DEFAULT '{"status":"AWAITING_OR_BYPASSED","tags":[],"confidence":null}'::jsonb,
  acknowledged_by TEXT,
  acknowledged_at TIMESTAMPTZ,
  assigned_to TEXT,
  assigned_at TIMESTAMPTZ,
  dispatched_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  client_event_id UUID,
  source_capture_utc TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure category constraint is up to date on existing tables
DO $$ BEGIN
  ALTER TABLE incidents DROP CONSTRAINT IF EXISTS incidents_category_check;
  ALTER TABLE incidents ADD CONSTRAINT incidents_category_check
    CHECK (category IN ('PERSONAL_SAFETY','GBV_DOMESTIC','GBV_SEXUAL_VIOLENCE','GBV_OTHER'));
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

ALTER TABLE incidents ADD COLUMN IF NOT EXISTS client_event_id UUID;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source_capture_utc TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_to TEXT;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

-- 3. Evidence Manifests (Forensic append-only vault)
CREATE TABLE IF NOT EXISTS evidence_manifests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  media_type TEXT NOT NULL,
  source_capture_utc TIMESTAMPTZ,
  server_receipt_utc TIMESTAMPTZ DEFAULT NOW(),
  location_provenance TEXT NOT NULL,
  media_sha256 TEXT NOT NULL,
  ed25519_signature TEXT NOT NULL,
  public_key_id TEXT NOT NULL,
  manifest_payload JSONB NOT NULL,
  media_storage_path TEXT
);
ALTER TABLE evidence_manifests ADD COLUMN IF NOT EXISTS media_storage_path TEXT;

-- 4. Evidence Audit Logs (Append-only action tracking)
CREATE TABLE IF NOT EXISTS evidence_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  timestamp_utc TIMESTAMPTZ DEFAULT NOW(),
  client_metadata JSONB DEFAULT '{}'::jsonb
);

-- 5. Safe Network: Trusted Contacts (Max 5 per user, with role & priority)
CREATE TABLE IF NOT EXISTS trusted_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  phone_e164 TEXT NOT NULL CHECK (phone_e164 ~ '^[+][1-9][0-9]{7,14}$'),
  role TEXT NOT NULL DEFAULT 'TRUSTED_PERSON' CHECK (role IN ('TRUSTED_PERSON','FAMILY','NEIGHBOUR','SUPPORT_ORG')),
  priority INT NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 5),
  notify_on TEXT[] NOT NULL DEFAULT ARRAY['P1_CRITICAL','P2_HIGH','P3_VERIFY','EXPLICIT_SOS','DURESS_PIN','COVERT_SOS','SHAKE_SOS'],
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  verified BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, phone_e164)
);

ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'TRUSTED_PERSON' CHECK (role IN ('TRUSTED_PERSON','FAMILY','NEIGHBOUR','SUPPORT_ORG'));
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 5);
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS notify_on TEXT[] NOT NULL DEFAULT ARRAY['P1_CRITICAL','P2_HIGH','P3_VERIFY','EXPLICIT_SOS','DURESS_PIN','COVERT_SOS','SHAKE_SOS'];
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Enforce maximum 5 active contacts per user
CREATE OR REPLACE FUNCTION check_trusted_contacts_limit() RETURNS TRIGGER AS $$
DECLARE
  active_count INT;
BEGIN
  IF NEW.is_active = TRUE THEN
    SELECT COUNT(*) INTO active_count
    FROM trusted_contacts
    WHERE user_id = NEW.user_id AND is_active = TRUE AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);
    IF active_count >= 5 THEN
      RAISE EXCEPTION 'A user may have at most 5 active trusted contacts';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_trusted_contacts_limit ON trusted_contacts;
CREATE TRIGGER trg_trusted_contacts_limit
  BEFORE INSERT OR UPDATE ON trusted_contacts
  FOR EACH ROW EXECUTE FUNCTION check_trusted_contacts_limit();

-- 6. Incident Escalation Notifications (Chain of dispatch)
CREATE TABLE IF NOT EXISTS incident_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES trusted_contacts(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'SENT' CHECK (status IN ('SENT','FAILED','ACKNOWLEDGED')),
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at TIMESTAMPTZ,
  attempt INT NOT NULL DEFAULT 1,
  escalated_from UUID REFERENCES trusted_contacts(id) ON DELETE SET NULL,
  ack_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Survivor-Owned Evidence Entries (Private documentation)
CREATE TABLE IF NOT EXISTS evidence_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('AUDIO','PHOTO','NOTE')),
  captured_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  gps GEOGRAPHY(POINT,4326),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  storage_path TEXT NOT NULL,
  manifest_id UUID REFERENCES evidence_manifests(id) ON DELETE SET NULL,
  shared_with JSONB NOT NULL DEFAULT '[]'::jsonb,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Verified Referral Directory (Non-invented, verified-flagged)
CREATE TABLE IF NOT EXISTS referral_partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('POLICE','GBV_DESK','SHELTER','COUNSELLING','LEGAL','HELPLINE','OTHER')),
  region TEXT NOT NULL DEFAULT 'NATIONAL',
  phone TEXT,
  hours TEXT,
  languages TEXT[] NOT NULL DEFAULT ARRAY['en','tn'],
  verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_source TEXT,
  verified_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Incident Referrals (Responder case handoffs)
CREATE TABLE IF NOT EXISTS incident_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES referral_partners(id) ON DELETE CASCADE,
  referred_by TEXT NOT NULL,
  referred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  outcome TEXT NOT NULL DEFAULT 'REFERRED' CHECK (outcome IN ('REFERRED','ACCEPTED','CONTACTED','FOLLOW_UP_REQUIRED','DECLINED')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. User Consents
CREATE TABLE IF NOT EXISTS user_consents (
  user_id TEXT PRIMARY KEY,
  location BOOLEAN NOT NULL DEFAULT TRUE,
  audio BOOLEAN NOT NULL DEFAULT FALSE,
  responder_contact BOOLEAN NOT NULL DEFAULT FALSE,
  share_evidence BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 11. Anonymous Survivor Identity & Devices
CREATE TABLE IF NOT EXISTS survivor_profiles (
  user_id TEXT PRIMARY KEY,
  alias_label TEXT,
  preferred_language TEXT NOT NULL DEFAULT 'en' CHECK (preferred_language IN ('en','tn')),
  emergency_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  device_label TEXT,
  device_key_hash TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS incident_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  location GEOGRAPHY(POINT,4326) NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  captured_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  received_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS registered_cameras_location_gist ON registered_cameras USING GIST(location);
CREATE INDEX IF NOT EXISTS incidents_location_gist ON incidents USING GIST(location);
CREATE INDEX IF NOT EXISTS incident_locations_location_gist ON incident_locations USING GIST(location);
CREATE INDEX IF NOT EXISTS incident_locations_incident_time ON incident_locations(incident_id,captured_at_utc DESC);
CREATE INDEX IF NOT EXISTS incidents_created_at_desc ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS incidents_priority_status ON incidents(priority,status);
CREATE UNIQUE INDEX IF NOT EXISTS incidents_client_event_id_unique ON incidents(client_event_id) WHERE client_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS evidence_audit_logs_incident_time ON evidence_audit_logs(incident_id,timestamp_utc);
CREATE INDEX IF NOT EXISTS evidence_manifests_incident_time ON evidence_manifests(incident_id,server_receipt_utc);
CREATE INDEX IF NOT EXISTS trusted_contacts_user_priority ON trusted_contacts(user_id, priority) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS incident_notifications_incident_id ON incident_notifications(incident_id);
CREATE INDEX IF NOT EXISTS incident_notifications_contact_status ON incident_notifications(contact_id, status);
CREATE INDEX IF NOT EXISTS evidence_entries_user_captured ON evidence_entries(user_id, captured_at_utc DESC);
CREATE INDEX IF NOT EXISTS evidence_entries_manifest_id ON evidence_entries(manifest_id);
CREATE INDEX IF NOT EXISTS referral_partners_type_region ON referral_partners(type, region);
CREATE INDEX IF NOT EXISTS referral_partners_verified ON referral_partners(verified);
CREATE INDEX IF NOT EXISTS incident_referrals_incident_id ON incident_referrals(incident_id);
CREATE INDEX IF NOT EXISTS incident_referrals_partner_id ON incident_referrals(partner_id);

-- PostGIS RPC for Authorized Nearby Cameras (150m bound)
CREATE OR REPLACE FUNCTION get_authorized_nearby_cameras(
  inc_lat DOUBLE PRECISION, inc_lng DOUBLE PRECISION, radius_m DOUBLE PRECISION DEFAULT 150.0
) RETURNS TABLE (
  id UUID, owner_name TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION, stream_url TEXT,
  azimuth_deg INT, fov_deg INT, distance_m DOUBLE PRECISION
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT c.id,c.owner_name,c.lat,c.lng,c.stream_url,c.azimuth_deg,c.fov_deg,
         ST_Distance(c.location,ST_SetSRID(ST_MakePoint(inc_lng,inc_lat),4326)::geography)
  FROM registered_cameras c
  WHERE c.is_authorized=TRUE AND c.connection_status='ONLINE'
    AND ST_DWithin(c.location,ST_SetSRID(ST_MakePoint(inc_lng,inc_lat),4326)::geography,radius_m)
  ORDER BY 8
$$;
REVOKE ALL ON FUNCTION get_authorized_nearby_cameras(DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_authorized_nearby_cameras(DOUBLE PRECISION,DOUBLE PRECISION,DOUBLE PRECISION) TO authenticated, service_role;

-- Demo Cameras
INSERT INTO registered_cameras(owner_name,location,lat,lng,azimuth_deg,fov_deg,is_authorized,stream_url)
SELECT v.owner,ST_SetSRID(ST_MakePoint(v.lng,v.lat),4326)::geography,v.lat,v.lng,v.az,v.fov,TRUE,'http://localhost:8080/video'
FROM (VALUES ('Gaborone CBD - SafeCity Pole #04',-24.6545,25.9085,180,110),('Main Mall Retail Opt-In Cam #02',-24.6580,25.9120,90,95)) v(owner,lat,lng,az,fov)
WHERE NOT EXISTS (SELECT 1 FROM registered_cameras c WHERE c.owner_name=v.owner);

-- Seed Unverified Referral Directory Placeholders (NO invented phone numbers)
INSERT INTO referral_partners (name, type, region, phone, hours, languages, verified, verified_source, notes)
SELECT v.name, v.type, v.region, NULL, v.hours, v.langs, FALSE, NULL, v.notes
FROM (VALUES
  ('Botswana Police Service — GBV / victim-support unit (TODO verify)', 'GBV_DESK', 'Gaborone', '24/7', ARRAY['en','tn'], 'Official police station GBV desk; contact number pending partner verification.'),
  ('Department of Gender Affairs (TODO verify)', 'COUNSELLING', 'NATIONAL', '07:30 - 16:30 Mon-Fri', ARRAY['en','tn'], 'Ministry of Youth, Gender, Sport and Culture counselling services; contact number pending partner verification.'),
  ('Women''s support NGOs — TODO verify with partners', 'SHELTER', 'Gaborone', '24/7 emergency intake', ARRAY['en','tn'], 'Non-governmental shelter and crisis intervention network; intake helpline pending formal agreement.'),
  ('Botswana Legal Aid / GBV Legal Assistance (TODO verify)', 'LEGAL', 'NATIONAL', '08:00 - 16:30 Mon-Fri', ARRAY['en','tn'], 'Legal counsel and court protection order assistance; contact pending partner verification.'),
  ('National Emergency GBV Helpline (TODO verify)', 'HELPLINE', 'NATIONAL', '24/7', ARRAY['en','tn'], 'National toll-free GBV crisis line; pending carrier and telecom partner verification.')
) v(name, type, region, hours, langs, notes)
WHERE NOT EXISTS (SELECT 1 FROM referral_partners r WHERE r.name = v.name);

-- Row Level Security (RLS) on ALL tables
DO $$ DECLARE t TEXT; BEGIN
  FOREACH t IN ARRAY ARRAY[
    'registered_cameras',
    'incidents',
    'evidence_manifests',
    'evidence_audit_logs',
    'trusted_contacts',
    'incident_locations',
    'devices',
    'incident_notifications',
    'evidence_entries',
    'referral_partners',
    'incident_referrals',
    'user_consents',
    'survivor_profiles'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon', t);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON TABLE public.%I FROM authenticated', t);
    EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', t);
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = t AND policyname = 'responders_read') THEN
      EXECUTE format('CREATE POLICY responders_read ON public.%I FOR SELECT TO authenticated USING (true)', t);
    END IF;
  END LOOP;
END $$;

-- Append-Only Triggers for Forensic & Audit Integrity
CREATE OR REPLACE FUNCTION deny_evidence_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Evidence manifests and audit logs are append-only'; END $$;
CREATE OR REPLACE FUNCTION deny_evidence_truncate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Evidence manifests and audit logs are append-only'; END $$;

DROP TRIGGER IF EXISTS evidence_audit_append_only ON evidence_audit_logs;
CREATE TRIGGER evidence_audit_append_only BEFORE UPDATE OR DELETE ON evidence_audit_logs
  FOR EACH ROW EXECUTE FUNCTION deny_evidence_mutation();
DROP TRIGGER IF EXISTS evidence_audit_no_truncate ON evidence_audit_logs;
CREATE TRIGGER evidence_audit_no_truncate BEFORE TRUNCATE ON evidence_audit_logs
  FOR EACH STATEMENT EXECUTE FUNCTION deny_evidence_truncate();

DROP TRIGGER IF EXISTS evidence_manifests_append_only ON evidence_manifests;
CREATE TRIGGER evidence_manifests_append_only BEFORE UPDATE OR DELETE ON evidence_manifests
  FOR EACH ROW EXECUTE FUNCTION deny_evidence_mutation();
DROP TRIGGER IF EXISTS evidence_manifests_no_truncate ON evidence_manifests;
CREATE TRIGGER evidence_manifests_no_truncate BEFORE TRUNCATE ON evidence_manifests
  FOR EACH STATEMENT EXECUTE FUNCTION deny_evidence_truncate();

-- Referral records are append-only audit logs
CREATE OR REPLACE FUNCTION deny_referral_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Incident referrals are append-only audit records'; END $$;
CREATE OR REPLACE FUNCTION deny_referral_truncate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Incident referrals are append-only audit records'; END $$;

DROP TRIGGER IF EXISTS incident_referrals_append_only ON incident_referrals;
CREATE TRIGGER incident_referrals_append_only BEFORE UPDATE OR DELETE ON incident_referrals
  FOR EACH ROW EXECUTE FUNCTION deny_referral_mutation();
DROP TRIGGER IF EXISTS incident_referrals_no_truncate ON incident_referrals;
CREATE TRIGGER incident_referrals_no_truncate BEFORE TRUNCATE ON incident_referrals
  FOR EACH STATEMENT EXECUTE FUNCTION deny_referral_truncate();

-- Realtime Publications
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incidents; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE evidence_manifests; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE evidence_audit_logs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_locations; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_notifications; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_referrals; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
