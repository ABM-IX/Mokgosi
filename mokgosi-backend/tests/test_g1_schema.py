from pathlib import Path
import re
import pytest

SCHEMA_PATH = Path(__file__).resolve().parents[2].joinpath("database", "schema.sql")
MIGRATION_PATH = Path(__file__).resolve().parents[2].joinpath("database", "migrations", "002_gbv.sql")


def test_schema_and_migration_files_exist():
    assert SCHEMA_PATH.exists(), f"Missing {SCHEMA_PATH}"
    assert MIGRATION_PATH.exists(), f"Missing {MIGRATION_PATH}"


def test_taxonomy_extension_in_schema_and_migration():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "COVERT_SOS" in sql
        assert "SHAKE_SOS" in sql
        for cat in ("PERSONAL_SAFETY", "GBV_DOMESTIC", "GBV_SEXUAL_VIOLENCE", "GBV_OTHER"):
            assert cat in sql


def test_trusted_contacts_safe_network_schema():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "role" in sql
        for role in ("TRUSTED_PERSON", "FAMILY", "NEIGHBOUR", "SUPPORT_ORG"):
            assert role in sql
        assert "priority" in sql
        assert "notify_on" in sql
        assert "is_active" in sql
        assert "check_trusted_contacts_limit" in sql
        assert "at most 5 active trusted contacts" in sql


def test_incident_notifications_schema():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "CREATE TABLE IF NOT EXISTS incident_notifications" in sql
        for status in ("SENT", "FAILED", "ACKNOWLEDGED"):
            assert status in sql
        assert "escalated_from" in sql
        assert "acked_at" in sql


def test_evidence_entries_schema():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "CREATE TABLE IF NOT EXISTS evidence_entries" in sql
        for kind in ("AUDIO", "PHOTO", "NOTE"):
            assert kind in sql
        assert "deleted_at" in sql
        assert "shared_with" in sql
        assert "manifest_id" in sql


def test_referral_partners_and_unverified_seed():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "CREATE TABLE IF NOT EXISTS referral_partners" in sql
        assert "verified BOOLEAN NOT NULL DEFAULT FALSE" in sql
        # Seeded placeholders must carry (TODO verify) and have NO phone numbers
        assert "Botswana Police Service — GBV / victim-support unit (TODO verify)" in sql
        assert "Department of Gender Affairs (TODO verify)" in sql
        assert "Women''s support NGOs — TODO verify with partners" in sql
        # Confirm phone is explicitly NULL in seed
        assert "SELECT v.name, v.type, v.region, NULL" in sql


def test_incident_referrals_and_append_only_triggers():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "CREATE TABLE IF NOT EXISTS incident_referrals" in sql
        assert "deny_referral_mutation" in sql
        assert "deny_referral_truncate" in sql
        assert "incident_referrals_append_only" in sql


def test_user_consents_and_survivor_profiles_schema():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    migration = MIGRATION_PATH.read_text(encoding="utf-8")

    for sql in (schema, migration):
        assert "CREATE TABLE IF NOT EXISTS user_consents" in sql
        assert "responder_contact BOOLEAN NOT NULL DEFAULT FALSE" in sql
        assert "share_evidence BOOLEAN NOT NULL DEFAULT FALSE" in sql
        assert "CREATE TABLE IF NOT EXISTS survivor_profiles" in sql
        # Anonymous: no real name or phone column required
        assert "phone_e164" not in sql.split("CREATE TABLE IF NOT EXISTS survivor_profiles")[1].split(");")[0]
        assert "full_name" not in sql.split("CREATE TABLE IF NOT EXISTS survivor_profiles")[1].split(");")[0]


def test_rls_covers_all_tables_and_revokes_anon():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    required_tables = [
        "registered_cameras",
        "incidents",
        "evidence_manifests",
        "evidence_audit_logs",
        "trusted_contacts",
        "incident_locations",
        "devices",
        "incident_notifications",
        "evidence_entries",
        "referral_partners",
        "incident_referrals",
        "user_consents",
        "survivor_profiles",
    ]
    for table in required_tables:
        assert f"'{table}'" in schema, f"Table {table} missing from RLS array in schema.sql"
    assert "REVOKE ALL ON TABLE public.%I FROM anon" in schema
    assert "REVOKE INSERT, UPDATE, DELETE ON TABLE public.%I FROM authenticated" in schema
    assert "CREATE POLICY responders_read ON public.%I FOR SELECT TO authenticated" in schema
