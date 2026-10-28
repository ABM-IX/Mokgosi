import base64
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "check_no_secrets.py"


def _scan_text():
    spec = importlib.util.spec_from_file_location("check_no_secrets", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.scan_text


def _jwt(role):
    # Built at runtime so this file never contains a literal token.
    def segment(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return f"{segment({'alg': 'HS256', 'typ': 'JWT'})}.{segment({'role': role, 'ref': 'demo'})}.{'s' * 16}"


def test_repository_has_no_committed_secrets():
    result = subprocess.run([sys.executable, str(SCRIPT)], cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_scanner_catches_each_secret_class():
    scan = _scan_text()
    hex64 = "ab" * 32
    assert scan("app.env.md", f"ED25519_PRIVATE_KEY_SEED={hex64}")
    assert scan("notes.md", f"random value {hex64}")
    assert not scan("notes.md", f"archived public key: {hex64}")
    assert scan("notes.md", f"public key next to the seed {hex64}")
    assert scan("app.js", f"const key = '{_jwt('anon')}'")
    assert not scan(".env.example", f"VITE_SUPABASE_ANON_KEY={_jwt('anon')}")
    assert scan(".env.example", f"SUPABASE_KEY={_jwt('service_role')}")
    assert scan("render.yaml", "    envVars:\n      - key: DEVICE_API_KEYS\n        value: abc123\n")
    assert not scan("render.yaml", "    envVars:\n      - key: DEVICE_API_KEYS\n        sync: false\n")
    assert scan(".env", "A=b")
    assert not scan("pubspec.lock", f"      sha256: {hex64}")
