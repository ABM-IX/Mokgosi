# MOKGOSI — Two-Pillar Personal Safety & GBV Response Network

**Tagline:** *"Your call for help. A connected response."*  
**Track:** FNB Hackathon — Safer Communities AND Gender-Based Violence (GBV) Response

Mokgosi addresses both dimensions of community safety through two pillars built on one shared, fault-tolerant engine:
- **Pillar A — Safer Communities (Public Space):** Active escort, municipal authorized CCTV mesh, and aggregated community insights.
- **Pillar B — GBV Response (Private/Home Space):** Covert help-seeking, survivor-owned evidence, safe network priority escalation, and accredited referral routing.

> [!IMPORTANT]
> **Core Engineering Invariants:**
> 1. **Response Works Across System Failures:** Trusted Person dispatch (`Route 1`) and Command Center persistence (`Route 2`) operate on isolated, independent paths. AI never gates, delays, downgrades, or cancels an alert.
> 2. **No False Assurance:** The mobile client only reports delivery after HTTP `2xx`; otherwise it persists the event in an idempotent offline queue (`client_event_id`) and triggers device SMS fallback.
> 3. **Covert Means Covert:** No sound, vibration, toasts, system notifications, or recent-apps preview for covert triggers. Disguised launcher (`.CalculatorAlias`) opens a working calculator (`7*6=42`). Safe PIN (`2580=`) unlocks the app; Duress PIN (`0852=`) silently sends an alert and stays on the calculator.
> 4. **Survivor Controls Their Data:** Evidence media is encrypted locally and private to the survivor until explicitly shared via sealed case bundles with expiring tokens.
> 5. **Silent Duress Override:** Responders are prohibited from contacting the survivor directly after a covert alert; coordination proceeds through the safe network or agreed welfare checks.
> 6. **Zero Fabricated Data:** Referral entries carry a `verified` flag. Unverified records are strictly suppressed from survivor screens, and no partner phone numbers or legal claims are invented.

---

## Real vs. Demo Truthfulness Matrix

| Capability | Real & Verified in Repo | Demo / Simulated Mode (`DEMO_MODE=true`) | Unverified Without Live Credentials / Hardware |
| :--- | :--- | :--- | :--- |
| **Dual-Routing & Idempotency** | FastAPI `trigger_incident` (`client_event_id` deduplication, 60s repeat coalescing, DB-down `202 ACCEPTED` fallback) | — | Live Supabase cloud latency |
| **Cryptographic Evidence Vault** | Persistent 32-byte `Ed25519` key (`ED25519_PRIVATE_KEY_SEED`), `SHA-256` hashing, `/api/v1/evidence/verify`, and standalone `verify_manifest.py` | Demo fallback frame bytes when `http://localhost:8080/video` is offline in `DEMO_MODE=true` | Hardware HSM custody & formal legal certification |
| **Safe Network Escalation** | 5-contact priority chain, signed `/ack/{token}` web confirmation links, sequential escalation upon non-acknowledgement | Simulated short escalation window (`ESCALATION_SECONDS=30`) for demo rehearsal | Live Twilio SMS delivery to Botswana `+267` carriers |
| **Calculator Disguise & Native Protection** | Android `.CalculatorAlias` labeled "Calculator", functional math engine, Safe PIN `2580=`, Duress PIN `0852=`, `FLAG_SECURE` recent-apps blanking | Fast PIN hints in debug rehearsal drawer | Physical OEM custom ROM task switcher variations |
| **Survivor-Owned Evidence Mode** | Silent audio/photo/note capture, AES encrypted local storage, multipart upload with Ed25519 signed manifests, 2h expiring case bundle ZIPs | Simulated audio/photo byte captures without hardware camera/mic locks | Physical camera shutter click on hardware-mandated regulatory devices |
| **Accredited Referral Routing** | `referral_partners` schema with `verified` flag, `incident_referrals` audit table, survivor suppression of unverified entries | Seeded Gaborone referral directory entries flagged `verified=false` | Bilateral partner MOUs (see `docs/PARTNERS_TODO.md`) |
| **Coarse Grid Spatial Analytics** | `GET /api/v1/analytics/hotspots` with ~500m grid clustering and strict k-anonymity suppression for cells < 5 incidents | Seeded demo incident density across Gaborone CBD | Real-time police CAD integration |
| **Authorized 150m CCTV Mesh** | PostGIS `ST_DWithin` 150m RPC (`is_authorized=TRUE`), directional FOV cones on Leaflet map, `AUTHORIZED_CCTV_FRAME` snapshot signing | 2 seeded Gaborone CBD camera rows pointing to `http://localhost:8080/video` | Live municipal RTSP/MJPEG camera streams |

---

## Quickstart: Run the Full Stack from Scratch

### 1. Database (`database/schema.sql` or `002_gbv.sql`)
Execute [`database/schema.sql`](database/schema.sql) inside your Supabase SQL Editor. The script is idempotent and configures PostGIS, enums (including `GBV_DOMESTIC`, `GBV_SEXUAL_VIOLENCE`, `COVERT_SOS`, `SHAKE_SOS`), all 13 core tables, spatial/B-tree indexes, Row Level Security revoking `anon` access, append-only triggers, and Realtime publications.

### 2. Backend (`mokgosi-backend/`)
```powershell
cd mokgosi-backend
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt

# Generate persistent 32-byte Ed25519 seed and configure .env
python scripts/gen_key.py
Copy-Item .env.example .env
# Set SUPABASE_URL, SUPABASE_KEY, ED25519_PRIVATE_KEY_SEED, DEVICE_API_KEYS, and DEMO_MODE=true

uvicorn main:app --env-file .env --reload
```
Health Check: `curl http://localhost:8000/health` returns `{"status":"HEALTHY","database":"REACHABLE"}` without crashing when DB is offline.

### 3. Responder Command Center (`mokgosi-dashboard/`)
```powershell
cd mokgosi-dashboard
Copy-Item .env.example .env
# Set VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, VITE_API_URL=http://localhost:8000, and VITE_DEMO_MODE=true

npm install
npm run dev
```
Open `http://localhost:5173`. Toggle between **Pillar A: Safer Communities** and **Pillar B: GBV Response** via the header tabs.

### 4. Flutter Android Client (`mokgosi-mobile/`)
```powershell
cd mokgosi-mobile
flutter pub get
flutter run --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 --dart-define=MOKGOSI_DEVICE_API_KEY=test-device-key-mokgosi-2026 --dart-define=MOKGOSI_DEMO_MODE=true
```
Onboarding lets users select **Getting around safely** (Pillar A) or **Support & safety** (Pillar B). The calculator disguise opens with `2580=` (Safe) and triggers covert SOS with `0852=`.

---

## Deploy-Readiness (Render & Supabase)

- **Render Backend Blueprint:** `mokgosi-backend/render.yaml` declares the web service, health check path (`/health`), and required environment variables (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ED25519_PRIVATE_KEY_SEED`, `DEVICE_API_KEYS`).
- **Free-Tier Cold Starts:** Note that free-tier instances sleep on inactivity (~50s cold-start). Mokgosi mobile client is specifically engineered with an idempotent offline queue and SMS fallback to ensure **zero lost alerts** even during a backend cold start. A paid instance or keep-alive cron is recommended for live demonstration.
- **Supabase Cloud Steps:**
  1. Execute `database/schema.sql` (single script setup).
  2. In Supabase Dashboard, create private storage bucket: `evidence-media`.
  3. Under Realtime, enable replication for `incidents`, `evidence_manifests`, `evidence_audit_logs`, and `incident_locations`.
  4. Create responder account in Auth and assign `app_metadata.role = "responder"`.

---

## Verification Test Suites

```powershell
# 1. Backend (FastAPI, Schemas, Evidence Vault, Safe Network, Referrals, Hotspots)
cd mokgosi-backend
.\.venv\Scripts\python.exe -m pytest -v
# Output: 42 passed in ~7.8s

# 2. Mobile (Flutter Analyze & Tests: Calculator, Covert SOS, Safe Network, Evidence Vault, 3-Shake)
cd mokgosi-mobile
flutter analyze
flutter test
# Output: 0 issues, 21 passed

# 3. Dashboard (Two-Pillar Console, Protocol Card, Referral Action, Hotspots, Realtime Latency)
cd mokgosi-dashboard
npm test
npm run build
# Output: 8 passed, clean production build in 2.27s (Realtime latency benchmark: 31ms median < 1000ms)
```

---

## Documentation Index
- **Two-Pillar Architecture:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Threat Model & Survivor Safety:** [`docs/PRIVACY_AND_SAFETY.md`](docs/PRIVACY_AND_SAFETY.md)
- **Partner Verification Checklist:** [`docs/PARTNERS_TODO.md`](docs/PARTNERS_TODO.md)
- **Setswana Localization Status:** [`docs/SETSWANA_L10N.md`](docs/SETSWANA_L10N.md)
- **4.5-Minute Pitch Script:** [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md)
- **Fault-Tolerance Rehearsal:** [`docs/REHEARSAL.md`](docs/REHEARSAL.md)
- **Progress & Acceptance Log:** [`PROGRESS.md`](PROGRESS.md)
