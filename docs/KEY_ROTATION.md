# Evidence signing key rotation

Evidence manifests are signed with Ed25519. The signed payload of every manifest carries
`public_key_id` (`mokgosi-ed25519-` + the first 8 hex characters of the public key).
`POST /api/v1/evidence/verify` looks the public key up **by that signed ID** in the server keyring.
A `public_key` supplied by the caller is ignored, so a self-signed manifest never verifies.

## Configuration

| Variable | Secret? | Meaning |
| :--- | :--- | :--- |
| `ED25519_PRIVATE_KEY_SEED` | **yes** | Active signing key. Render dashboard and gitignored `.env` only. |
| `ED25519_PUBLIC_KEYRING` | no (public keys) | Earlier keys as `<public_key_hex>:<status>`, comma-separated. |

Keyring statuses:

- `active`: the key from `ED25519_PRIVATE_KEY_SEED`; signs everything new.
- `retired`: rotated out normally. Still verifies what it signed before rotation (`valid: true, key_status: retired`).
- `compromised`: the private value is exposed, so anyone can forge with it. Verification returns
  `valid: false, reason: KEY_COMPROMISED` even when the signature matches. Evidence signed by such a key can
  only be trusted through an independent record, such as its row in the append-only `evidence_manifests` table.

`GET /api/v1/evidence/public-key` lists the whole keyring so offline verifiers can fetch archived keys.
Case bundles embed, per manifest, the public key that signed it (not just the current key).

## How to rotate

1. `cd mokgosi-backend && python scripts/gen_key.py` rewrites `.env`. It writes a new seed and moves the
   previous key's public half into `ED25519_PUBLIC_KEYRING` as `retired`. It prints only public material. Add
   `--compromised <public_key_hex>` to flag a leaked key.
2. Copy `ED25519_PRIVATE_KEY_SEED` and `ED25519_PUBLIC_KEYRING` from `.env` into the Render dashboard and redeploy.
3. Check: `GET /health` shows the new `signing_key_id`, and `GET /api/v1/evidence/public-key` lists the old key as `retired`.

Side effect: acknowledgement links (1 h) and case-bundle links (2 h) are HMAC-signed with the same seed, so
links issued before the rotation stop working once it happens.

## Key register (2026-10-29)

| Key ID | Status | Notes |
| :--- | :--- | :--- |
| `mokgosi-ed25519-7ae59000` | compromised | Full value committed to `render.yaml` in commit `2104b47` (repo is public). Render's `/health` reported a different key on 2026-10-29, and `evidence_manifests` on Supabase held 0 rows, so no stored evidence depends on it. |
| `mokgosi-ed25519-e0019460` | retired | Production key per Render `/health` on 2026-10-29. Not found in git history. Archived so anything it signed stays verifiable. |
| `mokgosi-ed25519-20bcf51c` | active (pending) | Generated 2026-10-29 into the local `mokgosi-backend/.env`. Production keeps signing with `e0019460` until the two values are copied into Render. |

Public keys (safe to publish):

- 7ae59000 public key: `7ae59000445732bb8b956288d6124afd0989ef708353489debe3ac5338ec1509`
- e0019460 public key: `e00194601a245d3e3ec01533098254e232606bc2c49d93c9017f8ae8ed1b71fc`
- 20bcf51c public key: `20bcf51c8d24ef9115952a34f192e98f2877e201c9334fdda4e605af798bc71c`
