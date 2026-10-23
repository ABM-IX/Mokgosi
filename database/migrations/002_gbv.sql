-- MOKGOSI Migration 002: Gender-Based Violence (GBV) Response & Safe Network Extension
-- Re-runnable migration script (DO $$ / IF NOT EXISTS pattern).

-- 1. Extend trigger_source enum with covert triggers
DO $$ BEGIN
  ALTER TYPE trigger_source ADD VALUE IF NOT EXISTS 'COVERT_SOS';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TYPE trigger_source ADD VALUE IF NOT EXISTS 'SHAKE_SOS';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2. Extend incidents category constraint to cover GBV taxonomy
DO $$ BEGIN
  ALTER TABLE incidents DROP CONSTRAINT IF EXISTS incidents_category_check;
  ALTER TABLE incidents ADD CONSTRAINT incidents_category_check
    CHECK (category IN ('PERSONAL_SAFETY', 'GBV_DOMESTIC', 'GBV_SEXUAL_VIOLENCE', 'GBV_OTHER'));
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 3. Extend trusted_contacts for safe network with priority, role, and notification scopes
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'TRUSTED_PERSON'
  CHECK (role IN ('TRUSTED_PERSON', 'FAMILY', 'NEIGHBOUR', 'SUPPORT_ORG'));
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 1
  CHECK (priority BETWEEN 1 AND 5);
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS notify_on TEXT[] NOT NULL
  DEFAULT ARRAY['P1_CRITICAL', 'P2_HIGH', 'P3_VERIFY', 'EXPLICIT_SOS', 'DURESS_PIN', 'COVERT_SOS', 'SHAKE_SOS'];
ALTER TABLE trusted_contacts ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Enforce a maximum of 5 active trusted contacts per user
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

CREATE INDEX IF NOT EXISTS trusted_contacts_user_priority ON trusted_contacts(user_id, priority) WHERE is_active = TRUE;

-- 4. Incident Escalation & Notification Records (audit of escalation chain)
CREATE TABLE IF NOT EXISTS incident_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES trusted_contacts(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'SENT' CHECK (status IN ('SENT', 'FAILED', 'ACKNOWLEDGED')),
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at TIMESTAMPTZ,
  attempt INT NOT NULL DEFAULT 1,
  escalated_from UUID REFERENCES trusted_contacts(id) ON DELETE SET NULL,
  ack_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS incident_notifications_incident_id ON incident_notifications(incident_id);
CREATE INDEX IF NOT EXISTS incident_notifications_contact_status ON incident_notifications(contact_id, status);

-- 5. Survivor Evidence Entries (private survivor-owned media and notes)
CREATE TABLE IF NOT EXISTS evidence_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('AUDIO', 'PHOTO', 'NOTE')),
  captured_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  gps GEOGRAPHY(POINT, 4326),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  storage_path TEXT NOT NULL,
  manifest_id UUID REFERENCES evidence_manifests(id) ON DELETE SET NULL,
  shared_with JSONB NOT NULL DEFAULT '[]'::jsonb,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS evidence_entries_user_captured ON evidence_entries(user_id, captured_at_utc DESC);
CREATE INDEX IF NOT EXISTS evidence_entries_manifest_id ON evidence_entries(manifest_id);

-- 6. Verified Referral Partners Directory (non-invented, verified-flagged)
CREATE TABLE IF NOT EXISTS referral_partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('POLICE', 'GBV_DESK', 'SHELTER', 'COUNSELLING', 'LEGAL', 'HELPLINE', 'OTHER')),
  region TEXT NOT NULL DEFAULT 'NATIONAL',
  phone TEXT,
  hours TEXT,
  languages TEXT[] NOT NULL DEFAULT ARRAY['en', 'tn'],
  verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_source TEXT,
  verified_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS referral_partners_type_region ON referral_partners(type, region);
CREATE INDEX IF NOT EXISTS referral_partners_verified ON referral_partners(verified);

-- Seed unverified category placeholders (NO invented phone numbers)
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

-- 7. Incident Referrals (action audit for responder handoffs)
CREATE TABLE IF NOT EXISTS incident_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES referral_partners(id) ON DELETE CASCADE,
  referred_by TEXT NOT NULL,
  referred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  outcome TEXT NOT NULL DEFAULT 'REFERRED' CHECK (outcome IN ('REFERRED', 'ACCEPTED', 'CONTACTED', 'FOLLOW_UP_REQUIRED', 'DECLINED')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS incident_referrals_incident_id ON incident_referrals(incident_id);
CREATE INDEX IF NOT EXISTS incident_referrals_partner_id ON incident_referrals(partner_id);

-- Append-only protection for incident_referrals (audit integrity)
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

-- 8. User Consents Table
CREATE TABLE IF NOT EXISTS user_consents (
  user_id TEXT PRIMARY KEY,
  location BOOLEAN NOT NULL DEFAULT TRUE,
  audio BOOLEAN NOT NULL DEFAULT FALSE,
  responder_contact BOOLEAN NOT NULL DEFAULT FALSE,
  share_evidence BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. Anonymous Survivor Profiles (random ID, no real name or phone required)
CREATE TABLE IF NOT EXISTS survivor_profiles (
  user_id TEXT PRIMARY KEY,
  alias_label TEXT,
  preferred_language TEXT NOT NULL DEFAULT 'en' CHECK (preferred_language IN ('en', 'tn')),
  emergency_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Row Level Security for all new tables
DO $$ DECLARE t TEXT; BEGIN
  FOREACH t IN ARRAY ARRAY[
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

-- 11. Supabase Realtime Publication
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_notifications; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE incident_referrals; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
