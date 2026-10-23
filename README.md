# MOKGOSI — Personal Safety & Response Network

**Tagline:** *"Your call for help. A connected response."*  
**Track:** FNB Hackathon — Safer Communities & Gender-Based Violence (GBV) Response

Mokgosi connects an active-escort personal safety mobile client (`mokgosi-mobile/`) with a fault-tolerant incident & forensic evidence engine (`mokgosi-backend/`) and a real-time responder command center (`mokgosi-dashboard/`).

> [!IMPORTANT]
> **Core Engineering Invariant:** The safety response works even when AI, the database, or the SMS provider fails.
> - **Independent Dual-Routing:** Trusted Person dispatch (`Route 1`) and Command Center persistence (`Route 2`) fail independently.
> - **Upgrade-Only AI Context:** Acoustic triage (`Route 3`) only raises priority (`P3/P2 → P1`) and never gates, delays, downgrades, or cancels an alert.
> - **No False Assurance:** The mobile client only reports delivery after HTTP `2xx`; otherwise it persists the event in an idempotent offline retry queue (`client_event_id`) and triggers the device SMS fallback.
> - **Covert Duress (`0852`):** Entering the Duress PIN (or 3 consecutive wrong PINs) silences haptics, replaces the navigation stack with a back-blocked `"Journey Completed"` decoy screen, and alerts responders with a **`SILENT DURESS — do NOT call or message the user`** warning.

---

## Real vs. Demo Truthfulness Matrix

| Capability | Real & Verified in Repo | Demo / Simulated Mode (`DEMO_MODE=true`) | Unverified Without Live Credentials / Hardware |
| :--- | :--- | :--- | :--- |
| **Dual-Routing & Idempotency** | FastAPI `trigger_incident` (`client_event_id` deduplication, 60s repeat coalescing, DB-down `202 ACCEPTED` fallback) | — | Live Supabase cloud latency |
| **Cryptographic Evidence Vault** | Persistent 32-byte `Ed25519` key (`ED25519_PRIVATE_KEY_SEED`), `SHA-256` hashing, `/api/v1/evidence/verify`, and offline `verify_manifest.py` | Demo fallback frame bytes when `http://localhost:8080/video` is offline in `DEMO_MODE=true` | Hardware HSM custody & formal legal certification |
| **Trusted Person Notifier** | 3-attempt exponential backoff, E.164 validation, `webhook` and `twilio` adapters | `NOTIFIER_PROVIDER=console` logs `DEMO ONLY` payload without sending SMS | Live Twilio SMS delivery to Botswana `+267` carriers (two-way SMS & numeric sender IDs unsupported in BW; see [Twilio Botswana SMS Guidelines](https://www.twilio.com/en-us/guidelines/bw/sms)) |
| **Acoustic Triage (`Route 3`)** | Non-blocking multipart upload, `AUDIO_CONTEXT_CLIP` Ed25519 signing, upgrade-only priority rule | `DETERMINISTIC_DEMO` profiles (`DISTRESSED`, `CONVERSATION`, `SILENT`) gated behind `DEMO_MODE=true` | Real YAMNet TFLite model inference (`UNAVAILABLE` when `DEMO_MODE=false`) |
| **Mobile Sensors & Foreground Service** | Android `EscortForegroundService` (`location\|microphone`), `sensors_plus` $\ge 3.5g$ math, `geolocator` GPS, `PopScope` decoy, salted `SHA-256` PINs | `Simulate Physical Impact (4.2g)`, `Simulate Airplane Mode`, and Gaborone CBD coordinate pin (`-24.6560, 25.9090`) | Physical Android OEM lock-screen wake (`showWhenLocked`), physical drop impact, and cellular SMS transmission |
| **Authorized 150m CCTV Mesh** | PostGIS `ST_DWithin` 150m RPC (`is_authorized=TRUE`), directional FOV cones on Leaflet map, `AUTHORIZED_CCTV_FRAME` snapshot signing | 2 seeded Gaborone CBD camera rows pointing to `http://localhost:8080/video` | Live municipal / retail RTSP/MJPEG camera feeds |

---

## Quickstart: Run the Full Stack from Scratch

### 1. Database (`database/schema.sql`)
Execute [`database/schema.sql`](database/schema.sql) inside your Supabase SQL Editor. The script is idempotent and configures PostGIS, enums, tables, spatial/B-tree indexes, Row Level Security (revoking `anon` access), `BEFORE UPDATE/DELETE/TRUNCATE` append-only triggers on `evidence_manifests` and `evidence_audit_logs`, and Realtime publications.

### 2. Backend (`mokgosi-backend/`)
```powershell
cd mokgosi-backend
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt

# Generate a persistent 32-byte Ed25519 seed and copy into your private .env
python scripts/gen_key.py
Copy-Item .env.example .env
# Edit .env: set SUPABASE_URL, SUPABASE_KEY, ED25519_PRIVATE_KEY_SEED, DEVICE_API_KEYS, and DEMO_MODE=true (for local demo)

uvicorn main:app --env-file .env --reload
```

### 3. Responder Command Center (`mokgosi-dashboard/`)
```powershell
cd mokgosi-dashboard
Copy-Item .env.example .env
# Edit .env: set VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, VITE_API_URL=http://localhost:8000, and VITE_DEMO_MODE=true (for local demo)

npm install
npm run dev
```

### 4. Flutter Android Client (`mokgosi-mobile/`)
The Android scaffold is committed in `mokgosi-mobile/android/`. If regenerating from a clean template:
```powershell
cd mokgosi-mobile
flutter create --platforms=android --project-name mokgosi_mobile --no-pub .
# Restore AndroidManifest.xml permissions, EscortForegroundService declaration, and build.gradle.kts coreLibraryDesugaring
flutter pub get
```
Run on the Android emulator (`10.0.2.2` reaches host `localhost:8000`; on a physical phone, replace `10.0.2.2` with your computer's LAN IP):
```powershell
flutter run --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 --dart-define=MOKGOSI_DEVICE_API_KEY=<device-key> --dart-define=MOKGOSI_DEMO_MODE=true
```

---

## Verification & Documentation
- **Backend tests:** `cd mokgosi-backend && .\.venv\Scripts\python.exe -m pytest -v` (24 passed)
- **Mobile analyzer & tests:** `cd mokgosi-mobile && flutter analyze && flutter test` (0 analyzer issues, 6 tests passed)
- **Dashboard tests & build:** `cd mokgosi-dashboard && npm test && npm run build` (3 tests passed, production build clean)
- **Architecture & Data Flow:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Threat Model & GBV Safety:** [`docs/PRIVACY_AND_SAFETY.md`](docs/PRIVACY_AND_SAFETY.md)
- **Fault-Tolerance Rehearsal:** [`docs/REHEARSAL.md`](docs/REHEARSAL.md)
- **4.5-Minute Pitch Walkthrough:** [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md)
