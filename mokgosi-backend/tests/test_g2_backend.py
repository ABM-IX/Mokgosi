import base64
import io
import json
import os
import zipfile
from datetime import datetime, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import main
from services.evidence_vault import verify_manifest
from services.safe_network import generate_ack_token, verify_ack_token
from services.evidence_service import generate_bundle_token, verify_bundle_token, verify_bundle_zip


@pytest.fixture
def g2_client(monkeypatch):
    monkeypatch.setenv("DEMO_MODE", "false")
    monkeypatch.setenv("DEVICE_API_KEYS", "g2-device-key-alice,g2-device-key-bob")
    monkeypatch.setenv("NOTIFIER_PROVIDER", "console")
    monkeypatch.setenv("ESCALATION_SECONDS", "0.01")
    monkeypatch.setenv("API_BASE_URL", "http://testserver")

    from tests.test_backend import FakeSupabase
    fake = FakeSupabase()
    monkeypatch.setattr(main, "get_db", lambda: fake)
    return TestClient(main.app), fake


def register(client, key="g2-device-key-alice"):
    """Anonymous registration; returns the server-issued user_id and headers carrying the device token."""
    res = client.post("/api/v1/devices/register", json={}, headers={"X-Device-Key": key})
    assert res.status_code == 200, res.text
    body = res.json()
    return body["user_id"], {"X-Device-Key": key, "X-Device-Token": body["device_token"]}


def responder_headers():
    return {"Authorization": "Bearer valid-responder-token"}


# 1. Contact CRUD + Max 5 Limit
def test_contact_crud_and_max_5_limit(g2_client):
    client, fake = g2_client
    alice, headers = register(client)

    # Create 5 contacts
    created_ids = []
    for i in range(1, 6):
        res = client.post(
            "/api/v1/network/contacts",
            json={
                "user_id": alice,
                "name": f"Contact {i}",
                "phone_e164": f"+2677100000{i}",
                "role": "FAMILY" if i == 1 else "TRUSTED_PERSON",
                "priority": i,
            },
            headers=headers,
        )
        assert res.status_code == 200
        contact = res.json()["contact"]
        assert contact["priority"] == i
        created_ids.append(contact["id"])

    # 6th contact must be rejected (400 Bad Request)
    rejected = client.post(
        "/api/v1/network/contacts",
        json={
            "user_id": alice,
            "name": "Contact 6",
            "phone_e164": "+26771000006",
            "role": "NEIGHBOUR",
            "priority": 5,
        },
        headers=headers,
    )
    assert rejected.status_code == 400
    assert "at most 5" in rejected.json()["detail"].lower()

    # List contacts
    list_res = client.get("/api/v1/network/contacts", headers=headers)
    assert list_res.status_code == 200
    contacts = list_res.json()["contacts"]
    assert len(contacts) == 5

    # Update contact 1 priority
    c1_id = created_ids[0]
    update_res = client.patch(
        f"/api/v1/network/contacts/{c1_id}",
        json={"priority": 2, "name": "Updated Contact 1"},
        headers=headers,
    )
    assert update_res.status_code == 200
    assert update_res.json()["contact"]["name"] == "Updated Contact 1"

    # Delete contact
    del_res = client.delete(f"/api/v1/network/contacts/{c1_id}", headers=headers)
    assert del_res.status_code == 200
    assert del_res.json()["deleted"] is True


# 2. Escalation chain: contact 1 unacknowledged -> escalates to contact 2
def test_escalation_chain_dispatches_contact_2_when_contact_1_unacked(g2_client, monkeypatch):
    client, fake = g2_client
    dispatched_messages = []

    def mock_deliver(message):
        dispatched_messages.append(message)

    monkeypatch.setitem(main.dispatch.__globals__["PROVIDERS"], "console", mock_deliver)

    # Seed 2 contacts for alice (the safe network only runs for a registered device token)
    alice, headers = register(client)
    fake.rows["trusted_contacts"] = [
        {"id": "c1-uuid", "user_id": alice, "name": "C1", "phone_e164": "+26771111111", "priority": 1, "is_active": True},
        {"id": "c2-uuid", "user_id": alice, "name": "C2", "phone_e164": "+26772222222", "priority": 2, "is_active": True},
    ]

    # Trigger incident for alice with GBV category
    res = client.post(
        "/api/v1/incidents/trigger",
        json={
            "user_id": "ignored-label",
            "trigger_type": "COVERT_SOS",
            "category": "GBV_DOMESTIC",
            "lat": -24.65,
            "lng": 25.90,
        },
        headers=headers,
    )
    assert res.status_code == 200
    assert res.json()["incident"]["priority"] == "P1_CRITICAL"

    # Both contact 1 and contact 2 should have been notified
    assert len(dispatched_messages) >= 2
    recipients = [m["recipient"] for m in dispatched_messages]
    assert "+26771111111" in recipients
    assert "+26772222222" in recipients

    # Check incident_notifications table
    notifs = fake.rows.get("incident_notifications", [])
    assert len(notifs) >= 2
    assert any(n.get("escalated_from") == "c1-uuid" for n in notifs)


# Invariant 1: Escalation succeeds even if DB logging fails
def test_escalation_succeeds_even_if_db_logging_fails(g2_client, monkeypatch):
    from services.safe_network import run_escalation_chain
    dispatched = []

    def mock_deliver(msg):
        dispatched.append(msg)

    monkeypatch.setitem(main.dispatch.__globals__["PROVIDERS"], "console", mock_deliver)

    # Mock client where table insert raises RuntimeError
    class BrokenDB:
        def table(self, _name):
            raise RuntimeError("Database connection down")

    outcomes = run_escalation_chain(
        incident_id="inc-999",
        user_id="user-xyz",
        category="GBV_DOMESTIC",
        priority="P1_CRITICAL",
        lat=-24.6,
        lng=25.9,
        client=BrokenDB(),
        escalation_seconds=0,
    )
    # The chain handled error gracefully and did not crash
    assert isinstance(outcomes, list)


# 3. Acknowledgement link rejects expired/tampered tokens
def test_ack_link_rejects_expired_and_tampered_tokens(g2_client):
    client, fake = g2_client

    # Valid token
    valid_token = generate_ack_token("inc-123", "c1-123", ttl_seconds=3600)
    info = verify_ack_token(valid_token)
    assert info["incident_id"] == "inc-123"
    assert info["contact_id"] == "c1-123"

    # GET /ack/{valid_token} returns HTML with form
    get_res = client.get(f"/ack/{valid_token}")
    assert get_res.status_code == 200
    assert "I've got this" in get_res.text

    # POST /ack/{valid_token} records acknowledgement
    post_res = client.post(f"/ack/{valid_token}")
    assert post_res.status_code == 200
    assert "Thank You" in post_res.text

    # Expired token
    expired_token = generate_ack_token("inc-123", "c1-123", ttl_seconds=-10)
    with pytest.raises(ValueError, match="expired"):
        verify_ack_token(expired_token)
    exp_res = client.get(f"/ack/{expired_token}")
    assert exp_res.status_code == 400
    assert "expired" in exp_res.text.lower()

    # Tampered token
    decoded = base64.urlsafe_b64decode(valid_token.encode()).decode()
    parts = decoded.split(":")
    tampered_raw = f"{parts[0]}:other-contact:{parts[2]}:{parts[3]}"
    tampered_token = base64.urlsafe_b64encode(tampered_raw.encode()).decode()

    with pytest.raises(ValueError, match="signature"):
        verify_ack_token(tampered_token)
    tamp_res = client.get(f"/ack/{tampered_token}")
    assert tamp_res.status_code == 400


# 4. Evidence entry round-trip, signed manifest, case bundle & tamper test
def test_evidence_entry_roundtrip_bundle_and_tamper_detection(g2_client):
    client, fake = g2_client
    alice, headers = register(client)

    # Store a note entry
    note_res = client.post(
        "/api/v1/evidence-entries",
        data={
            "user_id": alice,
            "kind": "NOTE",
            "notes": "Incident occurred at front gate.",
            "lat": "-24.654",
            "lng": "25.908",
        },
        headers=headers,
    )
    assert note_res.status_code == 200
    entry = note_res.json()["entry"]
    manifest = note_res.json()["signed_manifest"]
    assert entry["kind"] == "NOTE"
    assert manifest["media_type"] == "SURVIVOR_NOTE"
    assert verify_manifest(manifest, main.PUBLIC_KEY_HEX)

    # Store an audio entry
    audio_res = client.post(
        "/api/v1/evidence-entries",
        data={"user_id": alice, "kind": "AUDIO"},
        files={"media_file": ("statement.wav", b"RIFF-survivor-voice-recording", "audio/wav")},
        headers=headers,
    )
    assert audio_res.status_code == 200
    audio_entry = audio_res.json()["entry"]
    audio_manifest = audio_res.json()["signed_manifest"]
    assert audio_manifest["media_type"] == "SURVIVOR_AUDIO"
    assert verify_manifest(audio_manifest, main.PUBLIC_KEY_HEX)

    # List entries for alice
    list_res = client.get(f"/api/v1/evidence-entries?user_id={alice}", headers=headers)
    assert list_res.status_code == 200
    assert len(list_res.json()["entries"]) == 2

    # Share bundle with POLICE
    share_res = client.post(
        "/api/v1/evidence-entries/share",
        json={
            "user_id": alice,
            "entry_ids": [entry["id"], audio_entry["id"]],
            "recipient_type": "POLICE",
            "notes": "Case documentation for GBV desk intake.",
        },
        headers=headers,
    )
    assert share_res.status_code == 200
    share_data = share_res.json()
    download_url = share_data["download_url"]

    # Download bundle ZIP
    dl_res = client.get(download_url)
    assert dl_res.status_code == 200
    assert dl_res.headers["content-type"] == "application/zip"
    zip_bytes = dl_res.content

    # Verify bundle structure
    with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as zf:
        names = zf.namelist()
        assert "manifests.json" in names
        assert "README.txt" in names
        assert "verify_manifest.py" in names
        assert any(n.startswith("media/") for n in names)

    # Test clean bundle verification
    verification = verify_bundle_zip(zip_bytes)
    assert verification["valid"] is True, verification.get("error")
    assert verification["entries_verified"] == 2

    # Test 1-byte tamper in bundle ZIP causes verification to fail!
    tampered_zip_buf = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as src_zf:
        with zipfile.ZipFile(tampered_zip_buf, "w") as dst_zf:
            for item in src_zf.infolist():
                content = src_zf.read(item.filename)
                if item.filename.startswith("media/"):
                    # Tamper 1 byte in media file
                    content = content[:-1] + b"X"
                dst_zf.writestr(item, content)

    tamper_result = verify_bundle_zip(tampered_zip_buf.getvalue())
    assert tamper_result["valid"] is False
    assert "tampering detected" in tamper_result["error"].lower()


# 5. Multi-tenant privacy: User A cannot read User B's evidence entries
def test_user_cannot_read_another_users_evidence_entries(g2_client):
    client, fake = g2_client

    # Alice creates an entry
    alice, alice_headers = register(client)
    client.post(
        "/api/v1/evidence-entries",
        data={"kind": "NOTE", "notes": "Alice's private evidence."},
        headers=alice_headers,
    )

    # Bob attempts to read Alice's entries -> 403 Forbidden!
    _bob, bob_headers = register(client, "g2-device-key-bob")
    attempt = client.get(f"/api/v1/evidence-entries?user_id={alice}", headers=bob_headers)
    assert attempt.status_code == 403
    assert "another survivor" in attempt.json()["detail"].lower()
    # Without a user_id, Bob only ever sees his own (empty) vault.
    assert client.get("/api/v1/evidence-entries", headers=bob_headers).json()["entries"] == []


# 6. Referrals endpoint never returns unverified entries to survivors
def test_referrals_endpoint_filters_strictly_verified_only(g2_client):
    client, fake = g2_client

    # Seed 1 verified and 2 unverified partners
    verified_partner = {
        "id": "v-1",
        "name": "Botswana Police Service - Verified Central Station Desk",
        "type": "GBV_DESK",
        "region": "Gaborone",
        "phone": "+2673951111",
        "verified": True,
    }
    unverified_partner = {
        "id": "u-1",
        "name": "Women Support NGOs (TODO verify)",
        "type": "SHELTER",
        "region": "Gaborone",
        "phone": None,
        "verified": False,
    }
    fake.rows["referral_partners"] = [verified_partner, unverified_partner]

    # Survivor-facing directory
    res = client.get("/api/v1/referrals")
    assert res.status_code == 200
    partners = res.json()["partners"]
    assert len(partners) == 1
    assert partners[0]["name"] == "Botswana Police Service - Verified Central Station Desk"
    assert not any(p["name"] == "Women Support NGOs (TODO verify)" for p in partners)

    # Responder records referral for an incident
    incident_id = str(uuid4())
    fake.rows["incidents"] = [{"id": incident_id, "category": "GBV_DOMESTIC"}]

    ref_res = client.post(
        f"/api/v1/incidents/{incident_id}/referrals",
        json={"partner_id": "v-1", "notes": "Referred survivor to central GBV desk with safe escort."},
        headers=responder_headers(),
    )
    assert ref_res.status_code == 200
    assert ref_res.json()["referral"]["outcome"] == "REFERRED"


# 7. Hotspot endpoint suppresses small cells and leaks no identifiers
def test_hotspot_endpoint_suppresses_small_cells_and_coarsens_coordinates(g2_client):
    client, fake = g2_client

    # Seed 4 incidents at location A (below threshold of 5 -> must be SUPPRESSED)
    # Seed 6 incidents at location B (meets threshold of 5 -> must be INCLUDED)
    incidents = []
    for _ in range(4):
        incidents.append({"lat": -24.6511, "lng": 25.9011, "category": "PERSONAL_SAFETY"})
    for _ in range(6):
        incidents.append({"lat": -24.6622, "lng": 25.9122, "category": "PERSONAL_SAFETY"})

    fake.rows["incidents"] = incidents

    res = client.get("/api/v1/analytics/hotspots")
    assert res.status_code == 200
    data = res.json()
    hotspots = data["hotspots"]

    # Exactly 1 hotspot should be returned (the one with 6 incidents)
    assert len(hotspots) == 1
    cell = hotspots[0]
    assert cell["incident_count"] == 6
    assert cell["cell_size_meters"] == 500

    # Ensure no identifiers leak
    for key in ("user_id", "id", "client_event_id", "phone"):
        assert key not in cell


# 8. Health check checks DB reachability without failing process
def test_health_check_checks_db_without_crashing(g2_client):
    client, fake = g2_client
    res = client.get("/health")
    assert res.status_code == 200
    assert "database_reachable" in res.json()


def test_camera_registry_is_responder_only_and_hides_streams(g2_client):
    client, fake = g2_client
    fake.rows["registered_cameras"] = [
        {"id": "c1", "owner_name": "Shop A", "lat": -24.65, "lng": 25.9, "azimuth_deg": 90, "fov_deg": 90,
         "is_authorized": True, "connection_status": "ONLINE", "stream_url": "http://secret/stream"},
        {"id": "c2", "owner_name": "Offline B", "lat": -24.6, "lng": 25.9, "azimuth_deg": 0, "fov_deg": 90,
         "is_authorized": True, "connection_status": "OFFLINE", "stream_url": "http://x"},
        {"id": "c3", "owner_name": "Not opted in", "lat": -24.7, "lng": 25.9, "azimuth_deg": 0, "fov_deg": 90,
         "is_authorized": False, "connection_status": "ONLINE", "stream_url": "http://y"},
    ]
    assert client.get("/api/v1/cameras").status_code in (401, 403)
    _, device_headers = register(client)
    assert client.get("/api/v1/cameras", headers=device_headers).status_code in (401, 403)
    res = client.get("/api/v1/cameras", headers=responder_headers())
    assert res.status_code == 200
    cams = res.json()["cameras"]
    assert [c["id"] for c in cams] == ["c1"]
    assert "stream_url" not in cams[0]
