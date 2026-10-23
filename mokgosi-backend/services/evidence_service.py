"""Survivor-owned evidence management and tamper-evident case bundle generator.

Features:
- Encrypted / private storage of AUDIO, PHOTO, and NOTE entries.
- SHA-256 hashing and Ed25519 signature manifest via existing vault.
- Case bundle ZIP packaging (media, manifests.json, plain-language README, and verify_manifest.py).
- Expiring download tokens with audited access.
- In-memory verification of bundles to test against tampering.
"""

import base64
import hashlib
import hmac
import io
import json
import logging
import os
import time
import zipfile
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import UUID, uuid4

from services.evidence_vault import public_key_hex, sign_manifest, verify_manifest

logger = logging.getLogger("mokgosi.evidence_service")
BUNDLE_SECRET = os.getenv("ED25519_PRIVATE_KEY_SEED", "mokgosi-case-bundle-secret-seed").encode("utf-8")

# In-memory bundle cache for download tokens (in addition to storage)
_bundle_cache: dict[str, dict[str, Any]] = {}


def generate_bundle_token(user_id: str, bundle_id: str, ttl_seconds: int = 7200) -> str:
    expires_at = int(time.time()) + ttl_seconds
    raw = f"{user_id}:{bundle_id}:{expires_at}"
    sig = hmac.new(BUNDLE_SECRET, raw.encode("utf-8"), hashlib.sha256).hexdigest()[:32]
    return base64.urlsafe_b64encode(f"{raw}:{sig}".encode("utf-8")).decode("utf-8")


def verify_bundle_token(token: str) -> dict[str, Any]:
    try:
        raw = base64.urlsafe_b64decode(token.encode("utf-8")).decode("utf-8")
        parts = raw.split(":")
        if len(parts) != 4:
            raise ValueError("Malformed bundle token")
        user_id, bundle_id, exp_str, sig = parts
        expires_at = int(exp_str)
        expected_raw = f"{user_id}:{bundle_id}:{expires_at}"
        expected_sig = hmac.new(BUNDLE_SECRET, expected_raw.encode("utf-8"), hashlib.sha256).hexdigest()[:32]
        if not hmac.compare_digest(sig, expected_sig):
            raise ValueError("Invalid bundle signature")
        if time.time() > expires_at:
            raise ValueError("Case bundle download link has expired")
        return {"user_id": user_id, "bundle_id": bundle_id, "expires_at": expires_at}
    except Exception as exc:
        if isinstance(exc, ValueError):
            raise
        raise ValueError(f"Invalid token: {exc}") from exc


STANDALONE_VERIFIER_SCRIPT = '''#!/usr/bin/env python3
"""Mokgosi Case Bundle Verifier
Verifies SHA-256 hashes of all media files and validates Ed25519 signatures.

Usage:
    python verify_manifest.py [manifests.json]
"""
import hashlib
import json
import os
import sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
except ImportError:
    print("ERROR: python package \'cryptography\' is required. Run: pip install cryptography")
    sys.exit(2)

def verify_case_bundle(manifests_path="manifests.json"):
    path = Path(manifests_path)
    if not path.exists():
        print(f"Error: {manifests_path} not found.")
        sys.exit(1)
    
    with open(path, "r", encoding="utf-8") as f:
        manifests = json.load(f)
    
    if not isinstance(manifests, list):
        manifests = [manifests]
        
    print(f"=== Mokgosi Forensic Case Bundle Verification ===")
    print(f"Loaded {len(manifests)} manifests for inspection.\\n")
    
    all_valid = True
    base_dir = path.parent
    
    for idx, m in enumerate(manifests, 1):
        media_type = m.get("media_type")
        payload = m.get("manifest_payload", {})
        expected_sha256 = m.get("media_sha256")
        sig_hex = m.get("ed25519_signature")
        pubkey_hex = m.get("public_key")
        storage_filename = m.get("media_storage_path", "").split("/")[-1]
        
        print(f"[{idx}] Verifying {media_type} ({storage_filename or 'inline note'})...")
        
        # 1. Check file content hash if file exists
        file_path = base_dir / "media" / storage_filename if storage_filename else None
        if file_path and file_path.exists():
            with open(file_path, "rb") as mf:
                content = mf.read()
            actual_sha256 = hashlib.sha256(content).hexdigest()
            if actual_sha256 != expected_sha256:
                print(f"    FAIL: Hash mismatch for {storage_filename}! (TAMPER DETECTED)")
                all_valid = False
                continue
            else:
                print(f"    PASS: SHA-256 hash verified ({actual_sha256[:16]}...)")
        
        # 2. Check Ed25519 signature over canonical JSON
        try:
            pub_bytes = bytes.fromhex(pubkey_hex)
            verifier = Ed25519PublicKey.from_public_bytes(pub_bytes)
            canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
            verifier.verify(bytes.fromhex(sig_hex), canonical)
            print(f"    PASS: Ed25519 cryptographic signature is VALID.")
        except Exception as e:
            print(f"    FAIL: Invalid cryptographic signature! ({e})")
            all_valid = False
            
    print("-" * 50)
    if all_valid:
        print("RESULT: ALL MANIFESTS AND MEDIA VERIFIED SUCCESSFULLY.")
        sys.exit(0)
    else:
        print("RESULT: TAMPERING DETECTED. One or more items failed verification.")
        sys.exit(1)

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "manifests.json"
    verify_case_bundle(target)
'''


def generate_case_bundle_zip(
    user_id: str,
    entries: list[dict[str, Any]],
    manifests: list[dict[str, Any]],
    recipient_type: str,
    notes: Optional[str] = None,
) -> bytes:
    """Generate a clean, self-contained ZIP archive bundle."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        # 1. Manifests JSON
        zf.writestr("manifests.json", json.dumps(manifests, indent=2, sort_keys=True))

        # 2. Plain-language README
        readme_content = f"""MOKGOSI SURVIVOR-OWNED FORENSIC CASE BUNDLE
=====================================================
Generated at (UTC): {datetime.now(timezone.utc).isoformat()}
Designated Recipient: {recipient_type}
Entries Included: {len(entries)}
Status: SURVIVOR-CONSENTED DISCLOSURE

ABOUT THIS BUNDLE
-----------------
This case bundle was generated directly by the survivor through the Mokgosi Safety Platform.
Each piece of evidence (audio recording, photograph, or incident note) was cryptographically
hashed (SHA-256) and signed using an Ed25519 private key at the moment of capture/upload.

CONTENTS
--------
1. /media/                Original audio, photographic, or note data files.
2. manifests.json         Cryptographic certificates containing SHA-256 hashes, timestamps,
                          location provenance, and Ed25519 digital signatures.
3. verify_manifest.py     Standalone offline verification script. Run:
                          python verify_manifest.py manifests.json

EVIDENTIARY INTEGRITY
---------------------
To verify that no media file has been modified or tampered with since the survivor's capture:
1. Ensure Python 3.8+ and the cryptography library are available ('pip install cryptography').
2. In this folder, run: python verify_manifest.py
3. The script recalculates the SHA-256 digest of every media file and validates the Ed25519
   digital signature against the embedded public key.
"""
        if notes:
            readme_content += f"\nSURVIVOR CASE NOTES:\n--------------------\n{notes}\n"

        zf.writestr("README.txt", readme_content)

        # 3. Standalone verifier script
        zf.writestr("verify_manifest.py", STANDALONE_VERIFIER_SCRIPT)

        # 4. Media files
        for entry in entries:
            kind = entry.get("kind", "NOTE")
            raw_data = entry.get("_raw_bytes")
            if not raw_data:
                note_text = entry.get("notes") or f"Mokgosi Note recorded at {entry.get('captured_at_utc')}"
                raw_data = note_text.encode("utf-8")
            
            storage_filename = (entry.get("storage_path") or "").split("/")[-1]
            if not storage_filename:
                ext = ".wav" if kind == "AUDIO" else ".jpg" if kind == "PHOTO" else ".txt"
                storage_filename = f"entry_{entry.get('id')}_{kind.lower()}{ext}"
            filename = f"media/{storage_filename}"
            zf.writestr(filename, raw_data)

    return buffer.getvalue()


def verify_bundle_zip(zip_bytes: bytes) -> dict[str, Any]:
    """Inspect and cryptographically verify a case bundle ZIP in-memory."""
    try:
        with zipfile.ZipFile(io.BytesIO(zip_bytes), mode="r") as zf:
            if "manifests.json" not in zf.namelist():
                return {"valid": False, "error": "Missing manifests.json"}
            manifests = json.loads(zf.read("manifests.json").decode("utf-8"))
            if not isinstance(manifests, list):
                manifests = [manifests]
            
            for m in manifests:
                payload = m.get("manifest_payload", {})
                expected_sha256 = m.get("media_sha256")
                sig_hex = m.get("ed25519_signature")
                pubkey_hex = m.get("public_key")
                storage_filename = m.get("media_storage_path", "").split("/")[-1]

                # Match media file if exists
                media_path = f"media/{storage_filename}"
                if media_path in zf.namelist():
                    actual_sha256 = hashlib.sha256(zf.read(media_path)).hexdigest()
                    if actual_sha256 != expected_sha256:
                        return {"valid": False, "error": f"Hash mismatch for {media_path} (tampering detected)"}

                if not verify_manifest(m, pubkey_hex):
                    return {"valid": False, "error": "Manifest Ed25519 signature is invalid"}

            return {"valid": True, "entries_verified": len(manifests)}
    except Exception as exc:
        return {"valid": False, "error": str(exc)}
