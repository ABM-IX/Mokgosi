from copy import deepcopy
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import main
from services.evidence_vault import sign_manifest, verify_manifest
from services.priority_engine import assign_initial_priority


class Query:
    def __init__(self, client, table, op="select", value=None):
        self.client, self.table, self.op, self.value = client, table, op, value
        self.filters, self.max_rows, self.order_by = [], None, None

    def select(self, *_): self.op = "select"; return self
    def insert(self, value): self.op, self.value = "insert", value; return self
    def update(self, value): self.op, self.value = "update", value; return self
    def eq(self, key, value): self.filters.append(("eq", key, value)); return self
    def gte(self, key, value): self.filters.append(("gte", key, value)); return self
    def in_(self, key, values): self.filters.append(("in", key, values)); return self
    def order(self, key, desc=False): self.order_by = (key, desc); return self
    def limit(self, count): self.max_rows = count; return self

    def execute(self):
        if self.table == "evidence_audit_logs" and self.op == "insert" and self.client.audit_error:
            raise RuntimeError("audit service unavailable")
        if self.table == "incidents" and self.op == "insert" and self.client.incident_insert_error:
            raise RuntimeError("database write unavailable")
        rows = self.client.rows.setdefault(self.table, [])
        if self.op == "insert":
            values = self.value if isinstance(self.value, list) else [self.value]
            output = []
            for item in values:
                row = deepcopy(item)
                row.setdefault("id", str(uuid4()))
                row.setdefault("created_at", datetime.now(timezone.utc).isoformat())
                if self.table == "incidents" and row.get("client_event_id") and any(
                    x.get("client_event_id") == row["client_event_id"] for x in rows
                ):
                    raise RuntimeError("unique client_event_id")
                rows.append(row)
                output.append(deepcopy(row))
            return SimpleNamespace(data=output)
        matched = rows
        for kind, key, value in self.filters:
            if kind == "eq": matched = [row for row in matched if row.get(key) == value]
            elif kind == "in": matched = [row for row in matched if row.get(key) in value]
            elif kind == "gte": matched = [row for row in matched if (row.get(key) or "") >= value]
        if self.order_by:
            key, desc = self.order_by
            matched = sorted(matched, key=lambda row: row.get(key) or "", reverse=desc)
        if self.max_rows is not None: matched = matched[:self.max_rows]
        if self.op == "update":
            for row in matched: row.update(deepcopy(self.value))
        return SimpleNamespace(data=deepcopy(matched))


class FakeAuth:
    def get_user(self, token):
        if token != "valid-responder-token": raise RuntimeError("bad token")
        return SimpleNamespace(user=SimpleNamespace(id="verified-responder-007", app_metadata={"roles": ["responder"]}))


class FakeSupabase:
    def __init__(self, *, camera_error=False, audit_error=False, incident_insert_error=False):
        self.rows, self.camera_error, self.audit_error = {}, camera_error, audit_error
        self.incident_insert_error = incident_insert_error
        self.auth = FakeAuth()

    def table(self, name): return Query(self, name)
    def rpc(self, name, _args):
        if self.camera_error: raise RuntimeError("PostGIS unavailable")
        return SimpleNamespace(execute=lambda: SimpleNamespace(data=[{"id": "camera-1", "distance_m": 12.0}]))


@pytest.fixture
def client(monkeypatch):
    fake = FakeSupabase()
    monkeypatch.setattr(main, "get_db", lambda: fake)
    monkeypatch.setattr(main, "dispatch", lambda *args, **kwargs: {"success": True, "provider": "console", "attempts": 1})
    with TestClient(main.app) as test_client:
        yield test_client, fake


def trigger_body(**changes):
    body = {
        "user_id": "demo-survivor", "trusted_contact_phone": "+15555550100",
        "trigger_type": "EXPLICIT_SOS", "lat": -24.656, "lng": 25.909,
        "impact_g_force": 1.0, "client_event_id": str(uuid4()),
    }
    body.update(changes)
    return body


def device_headers(): return {"X-Device-Key": "test-device-key"}
def responder_headers(): return {"Authorization": "Bearer valid-responder-token"}


def test_database_failure_does_not_suppress_trusted_person_route(monkeypatch):
    delivered = []
    monkeypatch.setattr(main, "get_db", lambda: (_ for _ in ()).throw(RuntimeError("database down")))
    monkeypatch.setattr(main, "dispatch", lambda *args, **kwargs: delivered.append(args) or {"success": True})
    response = TestClient(main.app).post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    assert response.status_code == 202
    assert response.json()["incident_persisted"] is False
    assert response.json()["notification_state"] == "QUEUED"
    assert len(delivered) == 1


def test_incident_insert_failure_still_queues_trusted_person_dispatch(monkeypatch):
    fake = FakeSupabase(incident_insert_error=True)
    delivered = []
    monkeypatch.setattr(main, "get_db", lambda: fake)
    monkeypatch.setattr(main, "dispatch", lambda *args: delivered.append(args) or {"success": True})
    response = TestClient(main.app).post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    assert response.status_code == 202
    assert response.json()["persistence_state"] == "FAILED"
    assert len(delivered) == 1


def test_camera_and_audit_failures_do_not_undo_incident(monkeypatch):
    fake = FakeSupabase(camera_error=True, audit_error=True)
    monkeypatch.setattr(main, "get_db", lambda: fake)
    monkeypatch.setattr(main, "dispatch", lambda *args: {"success": True, "provider": "console", "attempts": 1})
    response = TestClient(main.app).post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    assert response.status_code == 200
    assert response.json()["incident_persisted"] is True
    assert response.json()["authorized_cameras"] == []
    assert len(fake.rows["incidents"]) == 1


def test_notifier_failure_logs_failure_and_keeps_incident(client, monkeypatch):
    test_client, fake = client
    monkeypatch.setattr(main, "dispatch", lambda *args: {"success": False, "provider": "twilio", "attempts": 3, "error": "provider down"})
    response = test_client.post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    assert response.status_code == 200
    assert len(fake.rows["incidents"]) == 1
    assert any(row["action"] == "TRUSTED_CONTACT_FAILED" for row in fake.rows["evidence_audit_logs"])


def test_same_client_event_id_returns_existing_incident(client):
    test_client, fake = client
    body = trigger_body()
    first = test_client.post("/api/v1/incidents/trigger", json=body, headers=device_headers())
    second = test_client.post("/api/v1/incidents/trigger", json=body, headers=device_headers())
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert len(fake.rows["incidents"]) == 1


def test_source_capture_time_is_persisted(client):
    test_client, fake = client
    source_time = "2026-10-23T08:15:00+02:00"
    response = test_client.post("/api/v1/incidents/trigger", json=trigger_body(source_timestamp_utc=source_time), headers=device_headers())
    assert response.status_code == 200
    assert fake.rows["incidents"][0]["source_capture_utc"] == source_time


def test_repeat_within_60_seconds_coalesces_and_only_raises_priority(client):
    test_client, fake = client
    first_body = trigger_body(trigger_type="MISSED_CHECKIN")
    first = test_client.post("/api/v1/incidents/trigger", json=first_body, headers=device_headers())
    assert main._coalesce_recent(fake, main.IncidentTriggerPayload(**first_body)) is not None
    second = test_client.post("/api/v1/incidents/trigger", json=trigger_body(trigger_type="EXPLICIT_SOS"), headers=device_headers())
    assert first.status_code == second.status_code == 200
    assert second.json()["persistence_state"] == "PERSISTED"
    assert second.json()["incident"]["priority"] == "P1_CRITICAL"
    assert len(fake.rows["incidents"]) == 1
    assert any(row["action"] == "REPEAT_TRIGGER" for row in fake.rows["evidence_audit_logs"])


@pytest.mark.parametrize(("trigger", "impact", "expected"), [
    ("EXPLICIT_SOS", 1, "P1_CRITICAL"), ("DURESS_PIN", 1, "P1_CRITICAL"),
    ("MOTION_IMPACT", 3.5, "P2_HIGH"), ("MISSED_CHECKIN", 1, "P3_VERIFY"),
    ("MISSED_CHECKIN", 3.5, "P2_HIGH"),
])
def test_priority_table(trigger, impact, expected):
    assert assign_initial_priority(trigger, impact) == expected


def test_acoustic_demo_only_upgrades_priority_and_worker_failure_is_neutral(client, monkeypatch):
    test_client, fake = client
    incident = {"id": str(uuid4()), "priority": "P3_VERIFY", "status": "CREATED"}
    fake.rows["incidents"] = [incident]
    url = f"/api/v1/incidents/{incident['id']}/acoustic-context"
    distress = test_client.post(url, data={"simulated_profile": "DISTRESSED"}, headers=responder_headers())
    assert distress.status_code == 200
    assert distress.json()["ai_context"]["model"] == "DETERMINISTIC_DEMO"
    assert fake.rows["incidents"][0]["priority"] == "P1_CRITICAL"
    fake.rows["incidents"][0]["priority"] = "P1_CRITICAL"
    conversation = test_client.post(url, data={"simulated_profile": "CONVERSATION"}, headers=responder_headers())
    silent = test_client.post(url, data={"simulated_profile": "SILENT"}, headers=responder_headers())
    assert conversation.status_code == silent.status_code == 200
    assert fake.rows["incidents"][0]["priority"] == "P1_CRITICAL"
    before = deepcopy(fake.rows["incidents"][0])
    monkeypatch.setattr(main, "analyze", lambda _profile: (_ for _ in ()).throw(RuntimeError("worker offline")))
    unavailable = test_client.post(url, data={"simulated_profile": "DISTRESSED"}, headers=responder_headers())
    assert unavailable.json()["ai_context"]["status"] == "UNAVAILABLE"
    assert fake.rows["incidents"][0] == before


def test_simulated_acoustic_profiles_are_disabled_outside_demo_mode(client, monkeypatch):
    test_client, fake = client
    monkeypatch.setenv("DEMO_MODE", "false")
    incident = {"id": str(uuid4()), "priority": "P3_VERIFY", "status": "CREATED"}
    fake.rows["incidents"] = [incident]
    response = test_client.post(f"/api/v1/incidents/{incident['id']}/acoustic-context",
                                data={"simulated_profile":"DISTRESSED"}, headers=responder_headers())
    assert response.json()["ai_context"]["status"] == "UNAVAILABLE"
    assert fake.rows["incidents"][0] == incident


def test_illegal_lifecycle_and_missing_auth_are_rejected(client):
    test_client, fake = client
    response = test_client.post("/api/v1/incidents/trigger", json=trigger_body())
    assert response.status_code == 401
    incident = {"id": str(uuid4()), "priority": "P3_VERIFY", "status": "CREATED"}
    fake.rows["incidents"] = [incident]
    lifecycle = test_client.patch(f"/api/v1/incidents/{incident['id']}/lifecycle", json={"new_status": "DISPATCHED"}, headers=responder_headers())
    assert lifecycle.status_code == 409
    invalid = test_client.post(f"/api/v1/incidents/{incident['id']}/audit", json={"action":"VIEW_INCIDENT"}, headers={"Authorization":"Bearer forged"})
    assert invalid.status_code == 401


def test_rate_limit_is_enforced_per_ip_and_device(client, monkeypatch):
    test_client, _ = client
    main._rate_windows.clear()
    monkeypatch.setattr(main, "RATE_LIMIT", 1)
    first = test_client.post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    second = test_client.post("/api/v1/incidents/trigger", json=trigger_body(), headers=device_headers())
    assert first.status_code == 200
    assert second.status_code == 429


def test_responder_identity_is_from_verified_token_not_request_body(client):
    test_client, fake = client
    incident = {"id": str(uuid4()), "priority": "P3_VERIFY", "status": "CREATED"}
    fake.rows["incidents"] = [incident]
    response = test_client.patch(f"/api/v1/incidents/{incident['id']}/lifecycle",
        json={"new_status":"ACKNOWLEDGED", "responder_id":"spoofed-operator"}, headers=responder_headers())
    assert response.status_code == 200
    assert response.json()["incident"]["acknowledged_by"] == "verified-responder-007"
    assert fake.rows["evidence_audit_logs"][-1]["actor_id"] == "verified-responder-007"


def test_signatures_are_stable_and_tampering_fails():
    first = sign_manifest(main.PRIVATE_KEY, "incident-1", b"first", "AUDIO", "demo", "2026-01-01T00:00:00Z")
    second = sign_manifest(main.PRIVATE_KEY, "incident-1", b"second", "AUDIO", "demo", "2026-01-01T00:00:00Z")
    assert first["public_key"] == second["public_key"] == main.PUBLIC_KEY_HEX
    assert verify_manifest(first, main.PUBLIC_KEY_HEX)
    assert verify_manifest(second, main.PUBLIC_KEY_HEX)
    tampered = deepcopy(first)
    tampered["manifest_payload"]["media_sha256"] = "0" * 64
    assert not verify_manifest(tampered, main.PUBLIC_KEY_HEX)


def test_missing_signing_seed_fails_instead_of_generating_ephemeral_key():
    from services.evidence_vault import load_private_key
    with pytest.raises(ValueError, match="required"):
        load_private_key("")


def test_database_schema_enforces_rls_and_append_only_artifacts():
    from pathlib import Path
    schema = Path(__file__).resolve().parents[2].joinpath("database", "schema.sql").read_text(encoding="utf-8")
    assert "ENABLE ROW LEVEL SECURITY" in schema
    assert "REVOKE ALL ON FUNCTION get_authorized_nearby_cameras" in schema
    assert "incidents_client_event_id_unique" in schema
    assert "evidence_audit_append_only" in schema
    assert "evidence_manifests_append_only" in schema


def test_trusted_notifier_retries_three_times(monkeypatch):
    from services import trusted_notifier
    attempts = []
    def failure(_message):
        attempts.append(1)
        raise RuntimeError("offline")
    monkeypatch.setitem(trusted_notifier.PROVIDERS, "test-failure", failure)
    outcome = trusted_notifier.dispatch("inc-1", "user", "+15555550100", "EXPLICIT_SOS", "P1_CRITICAL", -24.6, 25.9,
                                       provider="test-failure", backoff_seconds=0)
    assert outcome["success"] is False
    assert len(attempts) == 3


def test_acoustic_upload_persists_signed_manifest_and_accepts_device_key(client):
    test_client, fake = client
    incident = {"id": str(uuid4()), "priority": "P3_VERIFY", "status": "CREATED"}
    fake.rows["incidents"] = [incident]
    response = test_client.post(
        f"/api/v1/incidents/{incident['id']}/acoustic-context",
        data={"simulated_profile": "DISTRESSED"},
        files={"audio_file": ("clip.wav", b"RIFFdemo-audio-bytes", "audio/wav")},
        headers=device_headers(),
    )
    assert response.status_code == 200
    manifest = response.json()["signed_manifest"]
    assert manifest["media_type"] == "AUDIO_CONTEXT_CLIP"
    assert len(fake.rows.get("evidence_manifests", [])) == 1
    assert verify_manifest(manifest, main.PUBLIC_KEY_HEX)


def test_cctv_snapshot_signs_authorized_camera_and_refuses_unauthorized_camera(client):
    test_client, fake = client
    incident = {"id": str(uuid4()), "priority": "P1_CRITICAL", "status": "CREATED", "lat": -24.656, "lng": 25.909}
    fake.rows["incidents"] = [incident]
    ok = test_client.post(
        f"/api/v1/incidents/{incident['id']}/cctv-snapshot",
        json={"camera_id": "camera-1"},
        headers=responder_headers(),
    )
    assert ok.status_code == 200
    manifest = ok.json()["manifest"]
    assert manifest["media_type"] == "AUTHORIZED_CCTV_FRAME"
    assert verify_manifest(manifest, main.PUBLIC_KEY_HEX)
    assert any(row["action"] == "CCTV_SNAPSHOT_CAPTURED" for row in fake.rows.get("evidence_audit_logs", []))

    refused = test_client.post(
        f"/api/v1/incidents/{incident['id']}/cctv-snapshot",
        json={"camera_id": "unauthorized-outside-150m"},
        headers=responder_headers(),
    )
    assert refused.status_code == 403


def test_ten_rapid_duplicate_sos_taps_create_single_incident(client):
    test_client, fake = client
    event_id = str(uuid4())
    for _ in range(10):
        res = test_client.post(
            "/api/v1/incidents/trigger",
            json=trigger_body(client_event_id=event_id, category="GBV_DOMESTIC"),
            headers=device_headers(),
        )
        assert res.status_code == 200
    assert len(fake.rows["incidents"]) == 1
    assert fake.rows["incidents"][0]["category"] == "GBV_DOMESTIC"


