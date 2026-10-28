import hashlib

import pytest
from fastapi.testclient import TestClient

import main
from tests.test_backend import FakeSupabase

APP_KEY = {"X-Device-Key": "test-device-key"}


@pytest.fixture
def api(monkeypatch):
    fake = FakeSupabase()
    monkeypatch.setattr(main, "get_db", lambda: fake)
    return TestClient(main.app), fake


def register(client):
    body = client.post("/api/v1/devices/register", json={"preferred_language": "tn"}, headers=APP_KEY).json()
    return body, {**APP_KEY, "X-Device-Token": body["device_token"]}


def test_registration_is_anonymous_and_stores_only_a_token_hash(api):
    client, fake = api
    body, _ = register(client)
    assert fake.rows["devices"][0]["device_key_hash"] == hashlib.sha256(body["device_token"].encode()).hexdigest()
    assert body["device_token"] not in repr(fake.rows)
    assert set(fake.rows["survivor_profiles"][0]) <= {"id", "created_at", "user_id", "preferred_language"}


def test_app_key_alone_cannot_reach_private_data_or_the_safe_network(api, monkeypatch):
    client, fake = api
    assert client.get("/api/v1/network/contacts", headers=APP_KEY).status_code == 401
    assert client.get("/api/v1/me/consents", headers=APP_KEY).status_code == 401
    chains = []
    monkeypatch.setattr(main, "run_escalation_chain", lambda *args, **kwargs: chains.append(args) or [])
    res = client.post("/api/v1/incidents/trigger", headers=APP_KEY, json={
        "user_id": "someone-elses-id", "trigger_type": "EXPLICIT_SOS", "lat": -24.65, "lng": 25.9,
    })
    assert res.status_code == 200  # an SOS is never refused for lack of a token
    assert fake.rows["incidents"][0]["user_id"] == "unverified:someone-elses-id"
    assert chains == []


def test_contacts_are_owner_scoped_and_purge_really_deletes(api):
    client, fake = api
    alice, alice_headers = register(client)
    _bob, bob_headers = register(client)
    contact = client.post("/api/v1/network/contacts", headers=alice_headers,
                          json={"name": "Neo", "phone_e164": "+26771234567"}).json()["contact"]
    assert contact["user_id"] == alice["user_id"]
    assert client.patch(f"/api/v1/network/contacts/{contact['id']}", headers=bob_headers, json={"name": "x"}).status_code == 404
    assert client.delete(f"/api/v1/network/contacts/{contact['id']}", headers=bob_headers).status_code == 404
    assert client.patch("/api/v1/consents", headers=alice_headers, json={"audio": True}).status_code == 200

    purge = client.delete("/api/v1/me/data", headers=alice_headers)
    assert purge.status_code == 200
    assert purge.json()["deleted"] == {"trusted_contacts": 1, "evidence_entries": 0, "user_consents": 1,
                                       "survivor_profiles": 1, "devices": 1}
    assert not [row for row in fake.rows["trusted_contacts"] if row["user_id"] == alice["user_id"]]
    assert client.get("/api/v1/network/contacts", headers=alice_headers).status_code == 401  # token revoked
    assert client.get("/api/v1/network/contacts", headers=bob_headers).status_code == 200


def test_rate_limit_buckets_are_per_device_not_per_app_key(api, monkeypatch):
    client, _ = api
    _alice, alice_headers = register(client)
    _bob, bob_headers = register(client)
    monkeypatch.setattr(main, "RATE_LIMIT", 1)
    assert client.get("/api/v1/me/consents", headers=alice_headers).status_code == 200
    assert client.get("/api/v1/me/consents", headers=alice_headers).status_code == 429
    assert client.get("/api/v1/me/consents", headers=bob_headers).status_code == 200
