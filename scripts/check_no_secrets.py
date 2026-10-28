#!/usr/bin/env python3
"""Fail when likely secrets are about to be committed.

    python scripts/check_no_secrets.py           # scans every file git would commit
    python scripts/check_no_secrets.py PATH...   # scans just these files

Flags: 64-hex values that look like Ed25519 seeds, JWTs outside .env.example (Supabase service_role
JWTs everywhere), sb_secret_ keys, service_role key assignments, render.yaml secrets given as
`value:` instead of `sync: false`, tracked .env files, and values known to have leaked publicly.
A 64-hex value is allowed on a line that says what it is ("public", "sha256", "digest"), unless the
same line also says "seed", "private" or "secret". Findings never print the value itself.
Runs inside the backend test suite (mokgosi-backend/tests/test_no_secrets.py).
"""
import base64
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "build", "dist", ".dart_tool", "__pycache__",
             ".pytest_cache", ".gradle", ".idea"}
SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".jar", ".zip", ".apk", ".aab", ".so",
                 ".ttf", ".otf", ".woff", ".woff2", ".jks", ".keystore", ".pdf"}
LOCKFILES = {"pubspec.lock", "package-lock.json"}  # content-addressed package hashes only

HEX64 = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])")
JWT = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
SB_SECRET = re.compile(r"\bsb_secret_[A-Za-z0-9_-]{16,}")
SERVICE_ROLE_ASSIGNMENT = re.compile(r"(?i)service[_-]?role[_-]?(?:key|secret)?\s*[:=]\s*['\"]?([A-Za-z0-9._-]{24,})")
TOKEN = re.compile(r"[A-Za-z0-9_.-]{12,}")
PLACEHOLDER = re.compile(r"(?i)your_|replace|example|placeholder|changeme|<")
PUBLIC_CONTEXT = re.compile(r"(?i)public|sha256|sha-256|digest|checksum|integrity|fingerprint")
PRIVATE_CONTEXT = re.compile(r"(?i)seed|private|secret")
RENDER_KEY = re.compile(r"^\s*-\s*key:\s*([A-Z0-9_]+)\s*$")
RENDER_VALUE = re.compile(r"^\s*value:\s*(.*)$")
RENDER_SECRET_NAME = re.compile(r"SECRET|TOKEN|PASSWORD|SEED|PRIVATE|KEYRING|_KEYS?$|ANON_KEY|SUPABASE_URL|"
                                r"DATABASE_URL|DB_URL|TWILIO_ACCOUNT_SID|WEBHOOK_URL")

# Fingerprints of values that are public in this repo's history (docs/KEY_ROTATION.md). Kept as
# fingerprints so this file never contains the values themselves.
LEAKED_FINGERPRINTS = {
    "94e58058162696c66ea893e078354a9867a7739864f1086f2b581b7be0274afd": "fingerprint: signing key, commit 2104b47",
    "1b2816e2b5b62bd8a28d2631a5d0f90837b93ce72227417a9ee8be787876b58b": "fingerprint: device API key, commit 2104b47",
    "e6c7a36f6016891a14bb682f96ae3810c713119d70fdf72661e48ca127afc7c6": "fingerprint: device API key, commit 2a5c165",
}


def _redact(value: str) -> str:
    return f"{value[:4]}…({len(value)} chars)"


def _jwt_role(token: str) -> str | None:
    try:
        segment = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))
        return claims.get("role") if isinstance(claims, dict) else None
    except (ValueError, IndexError):
        return None


def scan_text(path: str, text: str) -> list[str]:
    name = Path(path).name
    findings: list[str] = []
    if name == ".env" or (name.startswith(".env.") and name != ".env.example"):
        findings.append(f"{path}: tracked env file; keep real values in gitignored .env files only")
    if name in LOCKFILES:
        return findings
    lines = text.splitlines()
    for number, line in enumerate(lines, start=1):
        where = f"{path}:{number}"
        for match in HEX64.finditer(line):
            if PRIVATE_CONTEXT.search(line) or not PUBLIC_CONTEXT.search(line):
                findings.append(f"{where}: 64-hex value that could be an Ed25519 seed {_redact(match.group())}")
        for match in JWT.finditer(line):
            role = _jwt_role(match.group())
            if role == "service_role":
                findings.append(f"{where}: Supabase service_role JWT {_redact(match.group())}")
            elif name != ".env.example":
                findings.append(f"{where}: JWT outside .env.example (role={role}) {_redact(match.group())}")
        for match in SB_SECRET.finditer(line):
            findings.append(f"{where}: Supabase secret key {_redact(match.group())}")
        for match in SERVICE_ROLE_ASSIGNMENT.finditer(line):
            if not PLACEHOLDER.search(match.group(1)):
                findings.append(f"{where}: service_role key assignment {_redact(match.group(1))}")
        for token in TOKEN.findall(line):
            label = LEAKED_FINGERPRINTS.get(hashlib.sha256(token.strip("._-").encode()).hexdigest())
            if label:
                findings.append(f"{where}: publicly leaked value ({label}); rotate it, never reuse it")
    if name.startswith("render") and name.endswith((".yaml", ".yml")):
        for index, line in enumerate(lines):
            key = RENDER_KEY.match(line)
            if not key or not RENDER_SECRET_NAME.search(key.group(1)):
                continue
            for follow in lines[index + 1:index + 4]:
                if RENDER_KEY.match(follow):
                    break
                value = RENDER_VALUE.match(follow)
                if value and value.group(1).strip().strip("'\""):
                    findings.append(f"{path}:{index + 1}: render.yaml sets {key.group(1)} inline; use `sync: false` "
                                    "and set it in the Render dashboard")
    return findings


def candidate_files(root: Path) -> list[Path]:
    try:
        listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                                cwd=root, capture_output=True, check=True).stdout.decode("utf-8").split("\0")
        paths = [root / rel for rel in listed if rel]
    except (OSError, subprocess.CalledProcessError):
        paths = [p for p in root.rglob("*") if p.is_file()]
    return [p for p in paths if p.is_file() and not SKIP_DIRS.intersection(p.relative_to(root).parts)
            and p.suffix.lower() not in SKIP_SUFFIXES]


def main(argv: list[str]) -> int:
    files = [Path(arg).resolve() for arg in argv] or candidate_files(ROOT)
    findings: list[str] = []
    for file in files:
        try:
            text = file.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        try:
            label = file.relative_to(ROOT).as_posix()
        except ValueError:
            label = str(file)
        findings.extend(scan_text(label, text))
    for finding in findings:
        print(finding)
    print(f"check_no_secrets: {len(files)} files scanned, {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
