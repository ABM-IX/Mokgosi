"""Stable Ed25519 signing and verification for evidence manifests, with a public keyring for rotation."""

import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

# Unsigned top-level manifest columns that must match the signed payload. Timestamps are excluded
# because Postgres re-formats timestamptz values on the way back out.
_MIRRORED_FIELDS = ("public_key_id", "media_sha256", "media_type", "location_provenance", "incident_id",
                    "media_storage_path")


def load_private_key(seed_hex: str | None = None) -> Ed25519PrivateKey:
    """Load the configured 32-byte seed; never generate an ephemeral key."""
    seed = seed_hex if seed_hex is not None else os.getenv("ED25519_PRIVATE_KEY_SEED", "")
    try:
        raw = bytes.fromhex(seed)
    except ValueError as exc:
        raise ValueError("ED25519_PRIVATE_KEY_SEED must be 64 hexadecimal characters") from exc
    if len(raw) != 32:
        raise ValueError(
            "ED25519_PRIVATE_KEY_SEED is required and must be 32 bytes (64 hex characters); "
            "generate one with scripts/gen_key.py"
        )
    return Ed25519PrivateKey.from_private_bytes(raw)


def public_key_hex(private_key: Ed25519PrivateKey) -> str:
    return private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    ).hex()


def key_id_for(public_hex: str) -> str:
    return f"mokgosi-ed25519-{public_hex[:8]}"


def parse_keyring(raw: str | None) -> dict[str, dict[str, str]]:
    """Parse ED25519_PUBLIC_KEYRING: comma-separated `<public_key_hex>[:retired|compromised]` entries.

    Retired keys still verify evidence they signed before rotation. Compromised keys (private seed
    exposed) are kept only so verification can say *why* it refuses them.
    """
    keyring: dict[str, dict[str, str]] = {}
    for entry in (raw or "").split(","):
        entry = entry.strip()
        if not entry:
            continue
        public_hex, _, status = entry.partition(":")
        public_hex, status = public_hex.strip().lower(), (status.strip().lower() or "retired")
        if status not in ("retired", "compromised"):
            raise ValueError(f"ED25519_PUBLIC_KEYRING status must be 'retired' or 'compromised', got {status!r}")
        try:
            Ed25519PublicKey.from_public_bytes(bytes.fromhex(public_hex))
        except ValueError as exc:
            raise ValueError("ED25519_PUBLIC_KEYRING entries must be 64-hex Ed25519 public keys") from exc
        keyring[key_id_for(public_hex)] = {"public_key": public_hex, "status": status}
    return keyring


def build_keyring(active_public_hex: str, raw_keyring: str | None = None) -> dict[str, dict[str, str]]:
    """Archived keys from the env plus the active signing key, which always wins on an ID clash."""
    keyring = parse_keyring(raw_keyring)
    keyring[key_id_for(active_public_hex)] = {"public_key": active_public_hex, "status": "active"}
    return keyring


def canonical_payload(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sign_manifest(
    private_key: Ed25519PrivateKey,
    incident_id: str,
    content: bytes,
    media_type: str,
    provenance: str,
    source_ts: str,
    media_storage_path: str | None = None,
) -> dict[str, Any]:
    """Hash the evidence bytes and sign a canonical manifest using a stable key."""
    now = datetime.now(timezone.utc).isoformat()
    digest = hashlib.sha256(content).hexdigest()
    public_hex = public_key_hex(private_key)
    payload: dict[str, Any] = {
        "platform": "MOKGOSI_NETWORK_V2",
        "incident_id": incident_id,
        "media_type": media_type,
        "source_capture_utc": source_ts,
        "server_receipt_utc": now,
        "location_provenance": provenance,
        "media_sha256": digest,
        "public_key_id": key_id_for(public_hex),
    }
    if media_storage_path:
        payload["media_storage_path"] = media_storage_path
    return {
        "incident_id": incident_id,
        "media_type": media_type,
        "source_capture_utc": source_ts,
        "server_receipt_utc": now,
        "location_provenance": provenance,
        "media_sha256": digest,
        "ed25519_signature": private_key.sign(canonical_payload(payload)).hex(),
        "public_key_id": payload["public_key_id"],
        "manifest_payload": payload,
        "public_key": public_hex,
        "media_storage_path": media_storage_path,
    }


def verify_manifest(manifest: dict[str, Any], public_hex: str | None = None) -> bool:
    """Return false for malformed, modified, or incorrectly signed manifests."""
    try:
        key_hex = public_hex or manifest.get("public_key")
        if not key_hex:
            return False
        key = Ed25519PublicKey.from_public_bytes(bytes.fromhex(key_hex))
        key.verify(
            bytes.fromhex(manifest["ed25519_signature"]),
            canonical_payload(manifest["manifest_payload"]),
        )
        return True
    except (InvalidSignature, KeyError, TypeError, ValueError):
        return False


def verify_with_keyring(manifest: Any, keyring: dict[str, dict[str, str]]) -> dict[str, Any]:
    """Pick the public key by the *signed* public_key_id, then verify.

    A caller-supplied `public_key` is ignored, so nobody can self-sign a manifest and have it accepted.
    """
    payload = manifest.get("manifest_payload") if isinstance(manifest, dict) else None
    if not isinstance(payload, dict):
        return {"valid": False, "reason": "MALFORMED_MANIFEST", "public_key_id": None, "key_status": None}
    key_id = payload.get("public_key_id")
    entry = keyring.get(key_id) if isinstance(key_id, str) else None
    result: dict[str, Any] = {"valid": False, "public_key_id": key_id, "key_status": entry["status"] if entry else None}
    if entry is None:
        return {**result, "reason": "UNKNOWN_KEY_ID"}
    for field in _MIRRORED_FIELDS:
        outer, inner = manifest.get(field), payload.get(field)
        if outer is not None and inner is not None and str(outer) != str(inner):
            return {**result, "reason": f"FIELD_MISMATCH:{field}"}
    if not verify_manifest(manifest, entry["public_key"]):
        return {**result, "reason": "INVALID_SIGNATURE"}
    if entry["status"] == "compromised":
        # The signature matches, but the private seed is public, so it proves nothing.
        return {**result, "reason": "KEY_COMPROMISED", "signature_matches": True}
    return {**result, "valid": True, "reason": None}
