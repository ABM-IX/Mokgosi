import importlib.util
from copy import deepcopy
from pathlib import Path
from uuid import uuid4

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient

import main
from services.evidence_vault import (
    build_keyring,
    key_id_for,
    load_private_key,
    parse_keyring,
    public_key_hex,
    sign_manifest,
)
from tests.test_backend import FakeSupabase


def _as_stored(manifest):
    """Shape of an evidence_manifests row: the convenience public_key field is not persisted."""
    return {k: v for k, v in manifest.items() if k != "public_key"}


def test_old_key_manifest_still_verifies_after_rotation_and_new_key_signs_new_ones(monkeypatch):
    old_key, new_key, leaked_key = (Ed25519PrivateKey.generate() for _ in range(3))
    before = sign_manifest(old_key, str(uuid4()), b"pre-rotation clip", "AUDIO_CONTEXT_CLIP", "demo", "2026-10-01T00:00:00Z")
    leaked = sign_manifest(leaked_key, str(uuid4()), b"anything", "AUDIO_CONTEXT_CLIP", "demo", "2026-10-01T00:00:00Z")

    new_public = public_key_hex(new_key)
    archived = f"{public_key_hex(old_key)}:retired,{public_key_hex(leaked_key)}:compromised"
    monkeypatch.setattr(main, "PRIVATE_KEY", new_key)
    monkeypatch.setattr(main, "PUBLIC_KEY_HEX", new_public)
    monkeypatch.setattr(main, "KEY_ID", key_id_for(new_public))
    monkeypatch.setattr(main, "KEYRING", build_keyring(new_public, archived))
    fake = FakeSupabase()
    monkeypatch.setattr(main, "get_db", lambda: fake)
    client = TestClient(main.app)

    old = client.post("/api/v1/evidence/verify", json=_as_stored(before)).json()
    assert old["valid"] is True
    assert old["key_status"] == "retired"
    assert old["public_key_id"] == key_id_for(public_key_hex(old_key))

    incident_id = str(uuid4())
    fake.rows["incidents"] = [{"id": incident_id, "priority": "P3_VERIFY", "status": "CREATED"}]
    signed = client.post(
        f"/api/v1/incidents/{incident_id}/acoustic-context",
        files={"audio_file": ("clip.wav", b"RIFF-after-rotation", "audio/wav")},
        headers={"X-Device-Key": "test-device-key"},
    ).json()["signed_manifest"]
    assert signed["public_key_id"] == key_id_for(new_public)
    fresh = client.post("/api/v1/evidence/verify", json=_as_stored(signed)).json()
    assert fresh["valid"] is True and fresh["key_status"] == "active"

    tampered = _as_stored(deepcopy(before))
    tampered["manifest_payload"]["media_sha256"] = "0" * 64
    assert client.post("/api/v1/evidence/verify", json=tampered).json()["valid"] is False

    refused = client.post("/api/v1/evidence/verify", json=_as_stored(leaked)).json()
    assert refused["valid"] is False and refused["reason"] == "KEY_COMPROMISED"

    # A stranger's self-signed manifest, even with its own public_key attached, is never accepted.
    forged = sign_manifest(Ed25519PrivateKey.generate(), incident_id, b"forged", "AUDIO_CONTEXT_CLIP", "demo", "2026-10-01T00:00:00Z")
    assert client.post("/api/v1/evidence/verify", json=forged).json()["reason"] == "UNKNOWN_KEY_ID"

    ring = client.get("/api/v1/evidence/public-key").json()["keyring"]
    assert {entry["status"] for entry in ring} == {"active", "retired", "compromised"}


def test_gen_key_rotates_env_file_and_never_prints_the_seed(tmp_path, capsys):
    spec = importlib.util.spec_from_file_location("gen_key", Path(__file__).resolve().parents[1] / "scripts" / "gen_key.py")
    gen_key = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen_key)

    def read_env(path):
        return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if "=" in line)

    env = tmp_path / ".env"
    env.write_text("SUPABASE_URL=https://example.supabase.co\n", encoding="utf-8")
    assert gen_key.main(["--env-file", str(env)]) == 0
    first_seed = read_env(env)["ED25519_PRIVATE_KEY_SEED"]
    assert first_seed not in capsys.readouterr().out

    assert gen_key.main(["--env-file", str(env)]) == 0
    second = read_env(env)
    assert second["ED25519_PRIVATE_KEY_SEED"] != first_seed
    assert second["ED25519_PRIVATE_KEY_SEED"] not in capsys.readouterr().out
    old_public = public_key_hex(load_private_key(first_seed))
    assert parse_keyring(second["ED25519_PUBLIC_KEYRING"])[key_id_for(old_public)] == {
        "public_key": old_public, "status": "retired",
    }
    assert second["SUPABASE_URL"] == "https://example.supabase.co"
