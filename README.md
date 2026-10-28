# MOKGOSI — Two-Pillar Personal Safety & GBV Response Network

**Tagline:** *"Your call for help. A connected response."*  
**Track:** FNB Hackathon — Safer Communities AND Gender-Based Violence (GBV) Response  
**Repository:** [https://github.com/ABM-IX/Mokgosi](https://github.com/ABM-IX/Mokgosi)

---

## 📌 Executive Summary & Architecture

Mokgosi is an emergency dispatch and civic protection system built on a shared, fault-tolerant infrastructure. It addresses community safety through two distinct operational pillars:

```
                                  ┌───────────────────────────────┐
                                  │   Mokgosi Dual-Pillar Engine   │
                                  └───────────────┬───────────────┘
                                                  │
                  ┌───────────────────────────────┴───────────────────────────────┐
                  ▼                                                               ▼
  ┌───────────────────────────────┐                               ┌───────────────────────────────┐
  │  Pillar A: Safer Communities  │                               │    Pillar B: GBV Response     │
  │        (Public Space)         │                               │    (Private / Home Space)     │
  ├───────────────────────────────┤                               ├───────────────────────────────┤
  │ • Active Walk-With-Me Escorts │                               │ • Covert Working Calculator   │
  │ • Auto-escalating countdowns  │                               │ • Safe PIN (2580=)            │
  │ • 150m PostGIS CCTV mesh      │                               │ • Duress Silent PIN (0852=)   │
  │ • Community responder routing │                               │ • Non-retaliation dispatch    │
  │ • Spatial hotspot clustering  │                               │ • Ed25519 Sealed Vault        │
  │ • Coarse-grid k-anonymity     │                               │ • Accredited referral network │
  └───────────────────────────────┘                               └───────────────────────────────┘
```

### Core Engineering & Safety Invariants
1. **Isolated Dual-Path Dispatch:** Trusted Contact SMS/Webhook notifications (`Route 1`) and Central Command CAD persistence (`Route 2`) run on isolated async paths. AI or network slow-downs never gate, delay, or cancel an alert.
2. **No False Assurance (Offline First):** The mobile client only displays a confirmed delivery state upon receiving HTTP `2xx`. If the connection is broken or the server is cold-starting, the alert is stored in an idempotent SQLite queue (`client_event_id`) and immediately triggers native device SMS fallback.
3. **Covert Invariant (Private Space):** No sound, vibration, banner, toast, or push notification triggers in covert mode. The app launcher icon is disguised as "Calculator" (`.CalculatorAlias`) with a fully functional math engine. 
   - `2580=` unlocks the authentic safety interface (Safe PIN).
   - `0852=` silently transmits a duress SOS to dispatch without UI change (Duress PIN).
4. **Non-Retaliation Dispatch Rule:** First responders and dispatchers are strictly barred from directly calling or texting the survivor's phone following a covert alert. Abusers often monitor phones; response coordination proceeds via designated safe contacts or discreet physical welfare checks.
5. **Survivor Data Sovereignty:** Evidentiary recordings and location feeds remain private to the survivor. Media is encrypted locally and only transmitted as sealed, Ed25519-signed manifest packages with 2-hour expiring access tokens upon survivor consent.
6. **Zero Fabricated Records:** The referral directory uses an explicit `verified` boolean schema flag. Unverified entries are suppressed from survivor interfaces.

---

## 🌐 Live Cloud Infrastructure

| Component | Provider / Tech | Live URL / Endpoint | Purpose |
| :--- | :--- | :--- | :--- |
| **Backend API** | Render (Python 3.11 / FastAPI) | [`https://mokgosi-backend.onrender.com`](https://mokgosi-backend.onrender.com) | REST API, dual-dispatch coordinator, evidence vault signer, PostGIS proxy |
| **Command Center** | Render (React + Vite Static Site) | [`https://mokgosi-dashboard.onrender.com`](https://mokgosi-dashboard.onrender.com) | Public "What is Mokgosi" landing page + authenticated CAD live triage console |
| **Cloud Database** | Supabase (PostgreSQL 15 + PostGIS) | [`https://svkqdjstcghtdjgmqzpd.supabase.co`](https://svkqdjstcghtdjgmqzpd.supabase.co) | Real-time incident persistence, PostGIS spatial RPCs, RLS, audit logs |
| **Mobile Client** | Flutter 3.24+ (Android / iOS / Web) | `mokgosi-mobile/` (APK / Debug) | Covert client, active escort countdown, biometric/PIN gate, offline queue |

---

## 🔑 Test & Demonstration Credentials

### 1. Dashboard CAD Console (First Responder / Dispatcher)
- **URL:** [https://mokgosi-dashboard.onrender.com](https://mokgosi-dashboard.onrender.com)
- **Action:** Open URL to view the public landing page. Click **"Auto-Fill Demo Dispatcher Credentials"** or enter:
  - **Operator ID:** `DISP_GABORONE_01`
  - **Password:** `MokgosiCAD2026!`
- **Result:** Grants access to the CAD Live Map, Realtime Incident Queue, PostGIS 150m CCTV matching, and Referral Partner handoff tool.

### 2. Mobile App (Citizen / Survivor)
- **Sign In Tab:**
  - **Email:** `citizen@mokgosi.org`
  - **Password:** `DemoCitizen2026!`
  - *(Or tap the **"Demo Auto-fill"** quick action button on the sign-in card).*
- **Covert Emergency Guest Access (No Account):**
  - Tap **"Quick Emergency Access (No Account)"** on the login screen.
  - Grants immediate SOS and escort protection without saving accounts or credentials to device storage.
- **Calculator Covert Unlock:**
  - **Safe PIN:** Type `2580=` to unlock the full Mokgosi user interface.
  - **Duress PIN:** Type `0852=` to silently dispatch an emergency alert while keeping the calculator visible.

---

## 📂 Repository Directory Map

```
Mokgosi/
├── database/
│   ├── schema.sql              # Idempotent master schema (PostGIS, 13 tables, RLS, RPC functions)
│   └── migrations/             # Incremental migration scripts (001_core, 002_gbv, 003_postgis)
├── mokgosi-backend/            # Python FastAPI microservice
│   ├── main.py                 # API entry point & routes (/incident/trigger, /evidence, /health)
│   ├── render.yaml             # Render service blueprint
│   ├── requirements.txt        # Backend dependencies
│   ├── scripts/gen_key.py      # Ed25519 32-byte key seed generator
│   └── tests/                  # Pytest test suite (42 tests covering dispatch, vault, auth)
├── mokgosi-dashboard/          # Dispatcher Command Center (React + Vite)
│   ├── src/
│   │   ├── components/         # LandingPortal, IncidentQueue, CadMap, ProtocolCard, CCTV
│   │   ├── services/           # Supabase client & backend REST client
│   │   └── App.jsx             # Main dashboard shell & login gate
│   ├── package.json            # Vite, React, Leaflet, Supabase-js
│   └── tests/                  # Vitest CAD test suite (9 tests)
├── mokgosi-mobile/             # Citizen Mobile Application (Flutter)
│   ├── lib/
│   │   ├── screens/            # LoginScreen, AppHomeScreen, CalculatorScreen, SafetySetupScreen
│   │   ├── services/           # OfflineQueue, DualPathDispatch, LocationService
│   │   └── main.dart           # App root, AuthGate, theme tokens
│   ├── android/                # Android native wrapper (FLAG_SECURE, CalculatorAlias launcher)
│   └── test/                   # Flutter test suite (27 unit & widget tests)
├── render.yaml                 # Root multi-service deployment blueprint for Render
└── docs/                       # In-depth architectural, privacy, and pitch documentation
```

---

## 🚀 Step-by-Step Setup Guide

### Step 1: Database Setup (Supabase)

1. **Log in to Supabase:** Open your project dashboard at [https://supabase.com](https://supabase.com).
2. **Execute Schema Migration:**
   - Go to **SQL Editor** in the left sidebar.
   - Open and copy the contents of [`database/schema.sql`](database/schema.sql).
   - Paste and click **Run**.
   - *This script is fully idempotent.* It enables `postgis`, creates custom ENUM types, provisions all 13 tables, establishes Row Level Security policies, creates the PostGIS camera RPC `get_authorized_nearby_cameras`, and seeds demo CBD cameras.
3. **Enable Realtime Subscriptions:**
   - In Supabase, navigate to **Database** -> **Replication** (or **Realtime**).
   - Ensure the following tables are enabled for realtime events:
     - `incidents`
     - `incident_locations`
     - `evidence_manifests`
     - `evidence_audit_logs`
4. **Create Private Storage Bucket:**
   - Go to **Storage** -> **New Bucket**.
   - Name: `evidence-media`.
   - Toggle **Public bucket: OFF** (all evidentiary media must be protected via authenticated RLS tokens).
5. **Obtain API Keys (Project Settings -> API):**
   - `Project URL`: `https://<your-project>.supabase.co`
   - `anon / public key`: Used in frontend dashboard and mobile client.
   - `service_role secret`: Used **only** by `mokgosi-backend` (never expose publicly).

---

### Step 2: Backend Setup (`mokgosi-backend/`)

#### Prerequisites
- Python 3.11+
- Git

#### Local Installation
```powershell
cd mokgosi-backend

# 1. Create and activate a virtual environment
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1    # On Windows PowerShell
# source .venv/bin/activate     # On Linux / macOS

# 2. Install dependencies
python -m pip install --upgrade pip
pip install -r requirements.txt

# 3. Configure environment variables
Copy-Item .env.example .env

# 4. Generate the Ed25519 signing seed (written into .env; only the public key is printed)
python scripts/gen_key.py
```

#### Configure `.env`
Update `.env` with your project values:
```ini
SUPABASE_URL=https://svkqdjstcghtdjgmqzpd.supabase.co
SUPABASE_KEY=<your_supabase_service_role_key>
ED25519_PRIVATE_KEY_SEED=<written by scripts/gen_key.py>
ED25519_PUBLIC_KEYRING=<written by scripts/gen_key.py on rotation>
DEVICE_API_KEYS=<long random app key; ships in the APK, so it is only a weak gate>
DEMO_MODE=false
NOTIFIER_PROVIDER=console
ESCALATION_SECONDS=30
RATE_LIMIT_PER_MINUTE=60
CORS_ORIGINS=http://localhost:5173,https://mokgosi-dashboard.onrender.com
EVIDENCE_STORAGE_BUCKET=evidence-media
```

#### Run & Verify
```powershell
# Start local API server on port 8000
uvicorn main:app --env-file .env --reload --port 8000

# In another terminal, verify the healthcheck
curl http://localhost:8000/health
# Response: {"status":"HEALTHY","database":"REACHABLE","timestamp":"..."}

# Run the backend test suite
pytest -v
# Verified: 42 passed
```

---

### Step 3: Dispatcher Dashboard Setup (`mokgosi-dashboard/`)

#### Prerequisites
- Node.js 18.x, 20.x, or 24.x
- npm

#### Local Installation
```powershell
cd mokgosi-dashboard

# 1. Install dependencies
npm install

# 2. Create environment file
Copy-Item .env.example .env
```

#### Configure `.env`
```ini
VITE_SUPABASE_URL=https://svkqdjstcghtdjgmqzpd.supabase.co
VITE_SUPABASE_ANON_KEY=<your_supabase_anon_public_key>
VITE_API_URL=http://localhost:8000   # Use https://mokgosi-backend.onrender.com when targeting live cloud
VITE_DEMO_MODE=false
VITE_SLA_ACK_THRESHOLD_SECONDS=60
```

#### Run, Test & Build
```powershell
# Start Vite development server
npm run dev
# Server running at: http://localhost:5173

# Run tests
npm test
# Verified: 9 passed

# Validate production build
npm run build
# Verified: Clean build generated into dist/
```

---

### Step 4: Mobile Application Setup (`mokgosi-mobile/`)

#### Prerequisites
- Flutter SDK 3.24+ ([https://flutter.dev](https://flutter.dev))
- Android Studio / Android SDK with platform tools
- Android Virtual Device (AVD) or physical device connected via USB with developer mode enabled

#### Local Installation
```powershell
cd mokgosi-mobile

# 1. Fetch Flutter packages
flutter pub get

# 2. Verify dependencies and syntax
flutter analyze
flutter test
# Verified: 27 passed
```

#### Running on Android Emulator / Physical Device
Flutter reads compile-time constants via `--dart-define`.

**A. Connecting to Live Cloud Backend:**
```powershell
flutter run `
  --dart-define=MOKGOSI_API_URL=https://mokgosi-backend.onrender.com `
  --dart-define=MOKGOSI_DEVICE_API_KEY=<your-app-key> `
  --dart-define=MOKGOSI_DEMO_MODE=false
```

**B. Connecting to Local Backend on Android Emulator:**
> Note: On Android emulators, `10.0.2.2` maps to `localhost` on the host machine.
```powershell
flutter run `
  --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 `
  --dart-define=MOKGOSI_DEVICE_API_KEY=<your-local-app-key> `
  --dart-define=MOKGOSI_DEMO_MODE=true
```

#### Building and Installing Debug APK via ADB
```powershell
flutter build apk --debug

# Install directly on active emulator or device:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r -d build\app\outputs\flutter-apk\app-debug.apk
```

---

## 🛠️ Deploying Updates to Render

The repository includes a root [`render.yaml`](render.yaml) blueprint coordinating both services:
1. `mokgosi-backend` (Web Service, Python 3.11, auto-runs `pip install -r requirements.txt`, start command `uvicorn main:app --host 0.0.0.0 --port $PORT`).
2. `mokgosi-dashboard` (Static Site, Node.js, build command `npm install && npm run build`, publish directory `dist`).

### Triggering Deployments
- Pushing commits to `origin/master` automatically triggers build and deployment pipelines on Render.
- If environment variables change, update them in the [Render Dashboard](https://dashboard.render.com).

---

## ⚠️ Essential Teammate Gotchas & Troubleshooting

### 1. Why are Android emulator screenshots black? (`FLAG_SECURE`)
- **Reason:** In [`MainActivity.kt`](mokgosi-mobile/android/app/src/main/kotlin/com/example/mokgosi_mobile/MainActivity.kt), `window.setFlags(WindowManager.LayoutParams.FLAG_SECURE)` is enabled by default. This is a life-saving safety requirement preventing spyware or abusers from recording a survivor's screen or inspecting app previews in the Android task switcher.
- **Development Workaround:** To inspect rendered UI on an emulator via CLI, use the UI Automator tree:
  ```powershell
  & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" shell "uiautomator dump /sdcard/ui.xml; cat /sdcard/ui.xml"
  ```
  *(Or temporarily comment out `FLAG_SECURE` in `MainActivity.kt` during UI prototyping).*

### 2. Render Free-Tier Cold Starts (~50s delay)
- Free-tier web services on Render spin down after 15 minutes of inactivity. The first request may take ~50 seconds to respond.
- **Client Invariant:** The Flutter mobile client handles this automatically using its offline idempotency queue. It will queue the alert, attempt exponential retries, and trigger device SMS fallback without losing data.
- **Recommendation:** Before a live demo, send a `curl https://mokgosi-backend.onrender.com/health` request to wake the instance.

### 3. PostGIS RPC Function Missing in Supabase
- If you see `function get_authorized_nearby_cameras does not exist`, verify that [`database/schema.sql`](database/schema.sql) was executed completely.
- Ensure the PostGIS extension is enabled: `CREATE EXTENSION IF NOT EXISTS postgis;`.

### 4. CORS Errors on Local Dashboard
- If your local dashboard on `http://localhost:5173` fails to fetch from `http://localhost:8000`, verify `CORS_ORIGINS` in `mokgosi-backend/.env` contains `http://localhost:5173`.

### 5. Flutter MethodChannel in Unit Tests
- When adding tests that access `PlatformStore` or native channels, register a mock handler in your test `setUp`:
  ```dart
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('mokgosi/platform'), (call) async => null);
  ```

---

## ⏱️ 15-Minute Teammate Onboarding Checklist

Follow this checklist to verify your complete development environment:

- [ ] **Step 1:** Clone repository and check out `master`.
- [ ] **Step 2:** Open [Supabase](https://supabase.com) and confirm the 13 tables are present under **Table Editor**.
- [ ] **Step 3:** Navigate to `mokgosi-backend`, activate `.venv`, and run `pytest -v` (All 42 tests should pass).
- [ ] **Step 4:** Navigate to `mokgosi-dashboard`, run `npm test` and `npm run dev`. Open `http://localhost:5173`, read the landing page, and sign in with `DISP_GABORONE_01`.
- [ ] **Step 5:** Navigate to `mokgosi-mobile`, run `flutter test` (All 27 tests should pass).
- [ ] **Step 6:** Launch `mokgosi-mobile` on emulator/device, sign in with `citizen@mokgosi.org` (or Quick Emergency Access), and test the Safe PIN (`2580=`) and Duress PIN (`0852=`).

---

## 📚 In-Depth Documentation Index

For detailed engineering rationales, partner requirements, and demo scripts:
- **Master System Overview:** [`docs/SYSTEM_OVERVIEW.md`](docs/SYSTEM_OVERVIEW.md)
- **Detailed Architecture Specification:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Threat Model & Survivor Safety:** [`docs/PRIVACY_AND_SAFETY.md`](docs/PRIVACY_AND_SAFETY.md)
- **Partner Verification & NGO Handoff:** [`docs/PARTNERS_TODO.md`](docs/PARTNERS_TODO.md)
- **Setswana Localization Guide:** [`docs/SETSWANA_L10N.md`](docs/SETSWANA_L10N.md)
- **Hackathon Pitch Script (4.5 Minutes):** [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md)
- **Fault-Tolerance Rehearsal Guide:** [`docs/REHEARSAL.md`](docs/REHEARSAL.md)
- **Project Progress & Test Audit Log:** [`PROGRESS.md`](PROGRESS.md)
