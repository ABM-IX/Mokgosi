-- MOKGOSI v2.1 schema; safe to re-run against a Supabase project.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN CREATE TYPE incident_priority AS ENUM ('P1_CRITICAL','P2_HIGH','P3_VERIFY');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE incident_status AS ENUM ('CREATED','ACKNOWLEDGED','ASSIGNED','DISPATCHED','RESOLVED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE trigger_source AS ENUM ('EXPLICIT_SOS','DURESS_PIN','MISSED_CHECKIN','MOTION_IMPACT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS registered_cameras (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_name TEXT NOT NULL,
 location GEOGRAPHY(POINT,4326) NOT NULL, lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL,
 azimuth_deg INT CHECK (azimuth_deg BETWEEN 0 AND 360), fov_deg INT DEFAULT 90,
 is_authorized BOOLEAN DEFAULT TRUE, connection_status TEXT DEFAULT 'ONLINE', stream_url TEXT NOT NULL,
 retention_policy_hours INT DEFAULT 72, created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS incidents (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id TEXT NOT NULL,
 trusted_contact_phone TEXT, trigger_type trigger_source NOT NULL,
 category TEXT NOT NULL DEFAULT 'PERSONAL_SAFETY' CHECK (category IN ('PERSONAL_SAFETY','GBV_DOMESTIC')),
 priority incident_priority NOT NULL, status incident_status DEFAULT 'CREATED',
 location GEOGRAPHY(POINT,4326) NOT NULL, lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL,
 impact_g_force DOUBLE PRECISION DEFAULT 1.0,
 ai_context JSONB DEFAULT '{"status":"AWAITING_OR_BYPASSED","tags":[],"confidence":null}'::jsonb,
 acknowledged_by TEXT, acknowledged_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'PERSONAL_SAFETY' CHECK (category IN ('PERSONAL_SAFETY','GBV_DOMESTIC'));
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS client_event_id UUID;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source_capture_utc TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_to TEXT;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMPTZ;
ALTER TABLE incidents ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS evidence_manifests (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
 media_type TEXT NOT NULL, source_capture_utc TIMESTAMPTZ, server_receipt_utc TIMESTAMPTZ DEFAULT NOW(),
 location_provenance TEXT NOT NULL, media_sha256 TEXT NOT NULL, ed25519_signature TEXT NOT NULL,
 public_key_id TEXT NOT NULL, manifest_payload JSONB NOT NULL, media_storage_path TEXT
);
ALTER TABLE evidence_manifests ADD COLUMN IF NOT EXISTS media_storage_path TEXT;
CREATE TABLE IF NOT EXISTS evidence_audit_logs (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
 actor_id TEXT NOT NULL, action TEXT NOT NULL, timestamp_utc TIMESTAMPTZ DEFAULT NOW(),
 client_metadata JSONB DEFAULT '{}'::jsonb
);
CREATE TABLE IF NOT EXISTS trusted_contacts (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id TEXT NOT NULL, name TEXT NOT NULL,
 phone_e164 TEXT NOT NULL CHECK (phone_e164 ~ '^[+][1-9][0-9]{7,14}$'),
 verified BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ DEFAULT NOW(), UNIQUE(user_id,phone_e164)
);
CREATE TABLE IF NOT EXISTS incident_locations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
 location GEOGRAPHY(POINT,4326) NOT NULL, lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL,
 captured_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(), received_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS devices (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id TEXT NOT NULL, device_label TEXT,
 device_key_hash TEXT NOT NULL UNIQUE, active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS registered_cameras_location_gist ON registered_cameras USING GIST(location);
CREATE INDEX IF NOT EXISTS incidents_location_gist ON incidents USING GIST(location);
CREATE INDEX IF NOT EXISTS incident_locations_location_gist ON incident_locations USING GIST(location);
CREATE INDEX IF NOT EXISTS incident_locations_incident_time ON incident_locations(incident_id,captured_at_utc DESC);
CREATE INDEX IF NOT EXISTS incidents_created_at_desc ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS incidents_priority_status ON incidents(priority,status);
CREATE UNIQUE INDEX IF NOT EXISTS incidents_client_event_id_unique ON incidents(client_event_id) WHERE client_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS evidence_audit_logs_incident_time ON evidence_audit_logs(incident_id,timestamp_utc);
CREATE INDEX IF NOT EXISTS evidence_manifests_incident_time ON evidence_manifests(incident_id,server_receipt_utc);

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

INSERT INTO registered_cameras(owner_name,location,lat,lng,azimuth_deg,fov_deg,is_authorized,stream_url)
SELECT v.owner,ST_SetSRID(ST_MakePoint(v.lng,v.lat),4326)::geography,v.lat,v.lng,v.az,v.fov,TRUE,'http://localhost:8080/video'
FROM (VALUES ('Gaborone CBD - SafeCity Pole #04',-24.6545,25.9085,180,110),('Main Mall Retail Opt-In Cam #02',-24.6580,25.9120,90,95)) v(owner,lat,lng,az,fov)
WHERE NOT EXISTS (SELECT 1 FROM registered_cameras c WHERE c.owner_name=v.owner);

-- RLS keeps anonymous clients from reading victim locations or camera endpoints.
DO $$ DECLARE t TEXT; BEGIN
 FOREACH t IN ARRAY ARRAY['registered_cameras','incidents','evidence_manifests','evidence_audit_logs','trusted_contacts','incident_locations','devices'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon',t);
  EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON TABLE public.%I FROM authenticated',t);
  EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated',t);
  EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role',t);
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t AND policyname='responders_read') THEN
   EXECUTE format('CREATE POLICY responders_read ON public.%I FOR SELECT TO authenticated USING (true)',t);
  END IF;
 END LOOP;
END $$;

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

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incidents; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE evidence_manifests; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE evidence_audit_logs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_locations; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
