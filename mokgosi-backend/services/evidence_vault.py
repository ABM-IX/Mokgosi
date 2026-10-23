"""Stable Ed25519 signing and verification for evidence manifests."""

import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


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
        "public_key_id": f"mokgosi-ed25519-{public_hex[:8]}",
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
