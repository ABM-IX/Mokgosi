"""Generate a fresh Ed25519 signing seed into a private env file. Prints only public key material.

If the env file already holds a seed, that key's *public* half is archived in ED25519_PUBLIC_KEYRING
(status "retired") so evidence it signed before rotation stays verifiable. See docs/KEY_ROTATION.md.

    python scripts/gen_key.py                       # rotates the seed in ./.env
    python scripts/gen_key.py --env-file .env.prod  # any other gitignored env file
    python scripts/gen_key.py --compromised <public_key_hex>   # also flag a leaked key
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402

from services.evidence_vault import key_id_for, load_private_key, parse_keyring, public_key_hex  # noqa: E402


def _set_var(lines: list[str], name: str, value: str) -> list[str]:
    updated, found = [], False
    for line in lines:
        if line.split("=", 1)[0].strip() == name and not line.lstrip().startswith("#"):
            updated.append(f"{name}={value}")
            found = True
        else:
            updated.append(line)
    if not found:
        updated.append(f"{name}={value}")
    return updated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env-file", default=".env", help="gitignored env file to write (default: .env)")
    parser.add_argument("--compromised", action="append", default=[], metavar="PUBLIC_KEY_HEX",
                        help="public key whose private seed was exposed; kept only to refuse it by name")
    args = parser.parse_args(argv)

    path = Path(args.env_file)
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    current = dict(line.split("=", 1) for line in lines if "=" in line and not line.lstrip().startswith("#"))
    keyring = parse_keyring(current.get("ED25519_PUBLIC_KEYRING"))

    archived = None
    try:
        old_public = public_key_hex(load_private_key(current.get("ED25519_PRIVATE_KEY_SEED", "").strip()))
        archived = key_id_for(old_public)
        keyring.setdefault(archived, {"public_key": old_public, "status": "retired"})
    except ValueError:
        pass  # no seed yet, or a placeholder: nothing to archive
    keyring.update(parse_keyring(",".join(f"{pub}:compromised" for pub in args.compromised)))

    new_key = Ed25519PrivateKey.generate()
    seed_hex = new_key.private_bytes(
        serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()
    ).hex()
    new_public = public_key_hex(new_key)
    keyring.pop(key_id_for(new_public), None)

    lines = _set_var(lines, "ED25519_PRIVATE_KEY_SEED", seed_hex)
    lines = _set_var(lines, "ED25519_PUBLIC_KEYRING",
                     ",".join(f"{entry['public_key']}:{entry['status']}" for entry in keyring.values()))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass

    print(f"New signing seed written to {path} (not printed). Copy ED25519_PRIVATE_KEY_SEED and")
    print("ED25519_PUBLIC_KEYRING from that file into the Render dashboard; never commit them.")
    print(f"public_key_id: {key_id_for(new_public)}")
    print(f"public_key:    {new_public}")
    for key_id, entry in keyring.items():
        print(f"keyring:       {key_id} {entry['status']}{' (previous active key)' if key_id == archived else ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
