"""Offline verifier: python verify_manifest.py manifest.json PUBLIC_KEY_HEX"""
import json
import sys
from services.evidence_vault import verify_manifest

if len(sys.argv) != 3:
    raise SystemExit("usage: python verify_manifest.py manifest.json PUBLIC_KEY_HEX")
with open(sys.argv[1], encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)
valid = verify_manifest(manifest, sys.argv[2])
print("VALID" if valid else "INVALID")
raise SystemExit(0 if valid else 1)
