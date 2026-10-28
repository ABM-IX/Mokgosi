# MOKGOSI — Master System Overview & Product Specification

> **Tagline:** *"Your call for help. A connected response."*  
> **Focus:** Personal safety and gender-based violence (GBV) response in Botswana  
> **Target Jurisdiction:** Botswana (National & Municipal Deployment)  
> **Architecture Version:** 3.0 (Two-Pillar Unified Safety Engine)

---

## 1. Executive Summary: What Mokgosi Is All About

**Mokgosi** (a Setswana word representing a communal alarm, emergency cry, or collective call for help) is a personal safety and gender-based violence (GBV) response platform, developed as a personal project and not yet released. 

The platform addresses a gap in Botswana's safety tools: conventional safety applications treat emergency response as a single, generic "panic button" with live tracking. In reality, public safety and domestic GBV represent two fundamentally different threat environments with conflicting physical constraints:

1. **Pillar A — Safer Communities (Public Space):**
   The threat is an unknown assailant, physical fall, or sudden crisis on a street or commute. The user wants visible tracking, active timed check-ins, deterrence, municipal CCTV coverage, and rapid emergency dispatch.
2. **Pillar B — GBV Response (Private/Home Space):**
   The person causing harm is often an intimate partner or family member within physical reach. The survivor may share a home, a phone, or cellular account with the abuser. Any audible alarm, vibration, notification, or suspicious app icon can precipitate severe violence. Here, safety requires **covert help-seeking, total device disguise, zero sensorial feedback, survivor-owned evidence documentation, and sequential escalation through a safe network of trusted individuals**.

Mokgosi solves both challenges through **one shared, fault-tolerant engineering engine** that guarantees reliable delivery even when the database, the cellular internet, or third-party AI services fail.

```
                                  ┌────────────────────────────────────────┐
                                  │                MOKGOSI                 │
                                  │      Unified Resilient Core Engine     │
                                  └───────────────────┬────────────────────┘
                                                      │
                       ┌──────────────────────────────┴──────────────────────────────┐
                       ▼                                                             ▼
         ┌───────────────────────────┐                                 ┌───────────────────────────┐
         │         PILLAR A          │                                 │         PILLAR B          │
         │     Safer Communities     │                                 │       GBV Response        │
         ├───────────────────────────┤                                 ├───────────────────────────┤
         │ • Public street commute   │                                 │ • Private domestic space  │
         │ • Active Escort (30s)     │                                 │ • Working Calculator App  │
         │ • 3.5g Impact detection   │                                 │ • Silent Duress (0852=)   │
         │ • 150m CCTV Mesh & Cones  │                                 │ • 3-Shake Covert Trigger  │
         │ • Signed frame capture    │                                 │ • Safe Network (5 chain)  │
         │ • Coarse Grid Hotspots    │                                 │ • Sealed Evidence Vault   │
         │ • Dispatch unit routing   │                                 │ • Verified Referral Desk  │
         └───────────────────────────┘                                 └───────────────────────────┘
```

---

## 2. Core Non-Negotiable Invariants

Every subsystem in Mokgosi is bound by five core architectural invariants:

1. **The Safety Response Works Across System Failures:**
   - **Independent Dual-Routing:** When an alert is triggered, notification to the survivor's Trusted Network (`Route 1`) and transmission to the Command Center (`Route 2`) run on isolated, decoupled paths. A failure in the database, cloud infrastructure, or SMS provider never blocks or suppresses the other path.
   - **AI Never Gates or Cancels:** Automated acoustic triage (`Route 3`) is strictly upgrade-only (`P3/P2 → P1`). It can never downgrade, delay, gate, or cancel an active human response.
2. **Zero False Assurance:**
   - The mobile application **never** presents an optimistic "Alert Sent" indicator unless the backend explicitly responds with an HTTP `2xx`.
   - If offline or out of cellular data, the event is immediately stored in an encrypted, idempotent offline queue (`client_event_id`) and device SMS fallback is initiated. The UI displays an honest status: *"Queued — no signal. Retrying automatically; SMS fallback triggered."*
3. **Covert Means Covert:**
   - On covert surfaces (`COVERT_SOS`, `SHAKE_SOS`, `DURESS_PIN`), there is **zero sound, zero vibration, zero toast notifications, and zero on-screen alerts**.
   - The launcher icon and title present as a standard, fully functioning calculator (`.CalculatorAlias`).
   - Android native window protection (`FLAG_SECURE`) blanks the recent-apps task switcher preview.
   - Persistent background service notifications display neutral user-chosen wording (*"Calculator Running"*), never safety or emergency terminology.
4. **Survivor Sovereignty & Data Isolation:**
   - Evidence media captured in Evidence Mode is encrypted locally and stored in a private bucket.
   - Nothing is auto-sent to responders or police except emergency SOS/duress alerts.
   - The survivor controls whether, when, and with whom evidence is shared via cryptographically sealed case bundles with 2-hour expiring access links.
5. **Strict Silent Protocol Override:**
   - Responders are strictly prohibited from calling or texting a survivor handset following a covert or duress alert. Coordination proceeds exclusively through the survivor's safe network or designated welfare check protocols.
6. **Strict Truthfulness & No Fabricated Data:**
   - No phone numbers, agency endorsements, legal compliance certifications, or partnership claims are invented. Referral directory entries carry an explicit `verified` boolean flag; unverified records are never presented as callable emergency numbers to survivors.

---

## 3. What We Have Built (Current System Inventory)

The Mokgosi repository comprises four integrated subsystems:

```
Mokgosi/
├── database/            # Supabase PostGIS schemas, migrations, RLS, & append-only triggers
├── mokgosi-backend/     # FastAPI incident engine, evidence service, safe network, & analytics
├── mokgosi-mobile/      # Flutter Android client with calculator disguise, escort, & evidence vault
├── mokgosi-dashboard/   # React + Vite Two-Pillar command center console with Leaflet map
└── docs/                # Architecture, threat models, partner checklists, & rehearsal guides
```

### 3.1. Database Layer ([`database/`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/database))
- **Schema & Migrations:** [`database/schema.sql`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/database/schema.sql) and [`database/migrations/002_gbv.sql`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/database/migrations/002_gbv.sql).
- **Core Tables (13 Tables):** `incidents`, `incident_locations`, `devices`, `registered_cameras`, `evidence_manifests`, `evidence_audit_logs`, `trusted_contacts`, `incident_notifications`, `evidence_entries`, `referral_partners`, `incident_referrals`, `user_consents`, `survivor_profiles`.
- **Spatial Engine:** PostGIS spatial queries (`ST_DWithin`, `ST_SetSRID`, `ST_MakePoint`) for authorized CCTV camera matching within 150m of an incident.
- **Security & RLS:** Row Level Security (RLS) enabled on all 13 tables. Public `anon` role access is completely revoked; service-role and authenticated responder roles are strictly partitioned.
- **Forensic Integrity:** PostgreSQL `BEFORE UPDATE OR DELETE OR TRUNCATE` triggers permanently block mutation or deletion on `evidence_manifests` and `evidence_audit_logs`.

### 3.2. Backend Incident & Forensic Engine ([`mokgosi-backend/`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-backend))
- **Framework:** Python 3.11 with FastAPI, Pydantic v2 schemas, and asynchronous background tasks.
- **Priority Engine:** Deterministic rule-based triage (`P1_CRITICAL`, `P2_HIGH`, `P3_VERIFY`) with 60-second repeat coalescing and upgrade-only priority rules.
- **Safe Network Escalation:** Manages up to 5 priority-ranked trusted contacts per user. Generates signed, tamper-evident, expiring web acknowledgement tokens (`/ack/{token}`) serving a zero-friction *"I've got this"* confirmation interface. Cascades to contact $N+1$ upon timeout.
- **Cryptographic Evidence Vault:** Process-stable persistent **Ed25519** private key seed (`ED25519_PRIVATE_KEY_SEED`). Signs canonical sorted JSON manifests over SHA-256 media hashes for legal audit trails. Includes standalone verifier [`verify_manifest.py`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-backend/verify_manifest.py).
- **Case Bundle Generator:** Compiles selected evidence entries into sealed ZIP packages containing media files, SHA-256 manifests, a plain-language legal README, and offline verification scripts, accessible via expiring signed tokens (`/api/v1/evidence-bundles/{token}`).
- **K-Anonymity Spatial Analytics:** Coarse ~500m grid clustering (`GET /api/v1/analytics/hotspots`) with strict suppression of any cell with fewer than 5 incidents (or fewer than 10 GBV incidents) to prevent re-identification.
- **Deploy Readiness:** Production `Dockerfile`, standalone [`render.yaml`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-backend/render.yaml), and resilient `/health` endpoint.

### 3.3. Mobile Client ([`mokgosi-mobile/`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-mobile))
- **Framework:** Flutter 3 with Dart 3, targeting Android 14+ (API 34).
- **Disguised Launcher (`.CalculatorAlias`):** Functional arithmetic calculator. Safe PIN (`2580=`) unlocks Mokgosi; Duress PIN (`0852=`) dispatches a silent `P1_CRITICAL` covert SOS and stays on the calculator without sensorial feedback.
- **Native Window Security:** `FLAG_SECURE` in Android [`MainActivity.kt`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-mobile/android/app/src/main/kotlin/bw/org/mokgosi/mokgosi_mobile/MainActivity.kt) blanks the app screenshot in the Android recent-apps task switcher.
- **Sensors & Telemetry:** Accelerometer threshold math ($\ge 3.5g$ impact detection), GPS tracking, and 3-shake gesture pattern detection within 2 seconds with automatic cooldown against false triggers.
- **Local Vault & Evidence Mode:** Silent capture controls for Notes, Audio, and Photos. AES-encrypted local sandbox (`flutter_secure_storage` + local store), timeline sync state indicators (*"Saved on this phone"* vs *"Backed up & signed"*), multi-select case bundle creation, and PIN-confirmed local emergency purge.
- **Dual Localization:** Native English and Setswana strings ([`mokgosi-mobile/lib/config/l10n.dart`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-mobile/lib/config/l10n.dart)) with Setswana terms documented in [`docs/SETSWANA_L10N.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/SETSWANA_L10N.md) under `NEEDS_NATIVE_REVIEW`.

### 3.4. Responder Command Center ([`mokgosi-dashboard/`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-dashboard))
- **Framework:** React 18 with Vite, Supabase Realtime client, and Leaflet tactical mapping.
- **Two-Pillar Switcher:** Instant toggle between **Pillar A (Safer Communities)** and **Pillar B (GBV Response)** with live active badge counts.
- **Urgency Queue & SLA Telemetry:** Priority sorting (`P1 > P2 > P3`), elapsed timers, and live Realtime latency benchmarking (< 1000ms SLA, measured at 31ms median).
- **GBV Case Console ([`GbvCaseView.jsx`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-dashboard/src/components/GbvCaseView.jsx)):**
  - Category and Survivor Consents displayed up front.
  - **Protocol Card:** High-visibility directive enforcing silent response (*"DO NOT CALL OR MESSAGE THE SURVIVOR"*), with partner confirmation placeholders.
  - **Safe Network Escalation Status:** Real-time visibility into who was notified, who acknowledged, and escalation timelines.
  - **Accredited Referral Panel:** Direct referral handoff logging to verified partners with immutable audit trail.
  - **Historical Pattern Signal:** Aggregates repeat incidents for the same device identity to highlight escalating patterns of domestic harm.
  - **Domestic CCTV Suppression:** Automatically hides camera cones for domestic/residential incidents, with an explicit toggle if the incident occurred in public.
- **Safer Communities Console:** Tactical live map with PostGIS 150m authorized camera FOV cones, live CCTV snapshot capture and Ed25519 signing, and a dedicated **Community Hotspots View** ([`HotspotsView.jsx`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/mokgosi-dashboard/src/components/HotspotsView.jsx)) enforcing k-anonymity privacy guarantees.

---

## 4. How the Two Pillars Work in Practice

### 4.1. Pillar A: Public Space Walk-Home Escort Flow
```
User starts Active Escort (30s)
  │
  ├─► User taps "Check In Now" (or countdown expires)
  │     └─► 15-second Haptic Check-In Window opens
  │           ├─► Safe PIN (2580): Escort resets cleanly
  │           └─► Duress PIN (0852): Covert decoy screen ("Journey Completed")
  │                 └─► Silent P1_CRITICAL alert to Command Center
  │
  └─► Accelerometer detects impact >= 3.5g (Man-Down Fall)
        └─► Check-in window expires without PIN
              └─► P2_HIGH alert dispatched automatically
                    └─► Command Center matches authorized cameras within 150m
                          └─► Operator views CCTV stream & captures signed Ed25519 snapshot
```

### 4.2. Pillar B: Coercive Domestic Environment Flow
```
Survivor at home under observation
  │
  ├─► Handset appears as standard working Calculator (.CalculatorAlias)
  │     ├─► Doing math: 7 * 6 = 42 (completely normal calculation)
  │     └─► Safe PIN 2580=: Unlocks Mokgosi Support & Safety home
  │
  ├─► Emergency help-seeking:
  │     ├─► Duress PIN 0852= entered in calculator, OR
  │     ├─► 3 hard shakes within 2s with screen locked (MotionTelemetry)
  │     │
  │     └─► ZERO sound, ZERO vibration, ZERO toast
  │           └─► Screen stays on neutral calculator
  │
  ├─► Dual-Routing Engine:
  │     ├─► Route 1 (Safe Network): SMS dispatched to Contact #1 with signed /ack/{token} link
  │     │     ├─► Contact #1 taps "I've got this" -> status ACKNOWLEDGED
  │     │     └─► If unacknowledged within timeout -> escalates automatically to Contact #2
  │     │
  │     └─► Route 2 (Command Center):
  │           ├─► GBV Console alerts in < 1 second
  │           ├─► Direct phone call/SMS to survivor is BLOCKED by system policy
  │           ├─► Historical Pattern Signal displays repeat domestic incident count
  │           ├─► Domestic CCTV cones are hidden for residential privacy
  │           └─► Operator records formal referral handoff to accredited shelter/support desk
  │
  └─► Evidence Documentation:
        └─► Survivor documents notes, silent audio, or silent photos in encrypted vault
              └─► Generates sealed case bundle ZIP with SHA-256 manifests for legal aid intake
```

---

## 5. What We Are Trying to Achieve at the End of the Day

### 5.1. The Societal Mission in Botswana
Botswana faces severe challenges with gender-based violence, intimate partner homicides, and street safety risks. At the end of the day, Mokgosi aims to achieve four systemic outcomes:

1. **Eliminating the Trap of the "Panic Button":**
   Traditional panic apps assume the user is free to shout, press a siren, or receive an emergency callback. In domestic coercion, this gets survivors killed. Mokgosi provides a survival-first mechanism that works covertly within the abuser's sight.
2. **Decoupling Help from Data & Airtime Wealth:**
   Emergencies do not wait for a user to have a data bundle. By coupling an idempotent offline queue with dual-routing SMS fallback and advocating for zero-rated telecom gateways, Mokgosi ensures that vulnerability is never gated by airtime poverty.
3. **Survivor Sovereignty Over Legal Evidence:**
   In GBV prosecutions, cases frequently collapse due to lack of contemporaneous evidence or claims of digital tampering. By providing an in-app vault that hashes media at capture time and signs manifests with Ed25519 cryptography, Mokgosi empowers survivors to own an unalterable evidentiary record for court protection orders.
4. **Actionable Community Insights Without Surveillance Overreach:**
   Municipalities and law enforcement need spatial data to allocate street lighting, patrols, and support desks. By enforcing coarse grid aggregation (~500m) and strict k-anonymity suppression (< 5 incidents), Mokgosi provides actionable crime analytics without exposing any individual survivor or household.

### 5.2. The Path to Production Deployment
Mokgosi is an honest, production-ready engineering prototype. To transition into live deployment across Botswana, the following verified milestones must be completed:

```mermaid
gantt
    title Mokgosi Operational Rollout Roadmap
    dateFormat  YYYY-MM
    section Regulatory & Legal
    Botswana Data Protection Act (DPA 2018) Registration :2026-11, 2026-12
    High Court Legal Opinion on Ed25519 Admissibility    :2026-11, 2027-01
    section Institutional MOUs
    Botswana Police Service (BPS) GBV Desk SOPs          :2026-12, 2027-02
    Dept of Gender Affairs Shelter Coordination          :2027-01, 2027-03
    Kagisano Women's Shelter Helpline Integration        :2026-12, 2027-02
    section Telecom Infrastructure
    Mascom / Orange / BTC Zero-Rated Shortcode Gateway   :2027-01, 2027-03
    Carrier Dual-Routing SMS Latency Guarantees          :2027-02, 2027-04
    section Community Localization
    Native Setswana Review of L10n Strings               :2026-11, 2026-12
    Community Field Trials in Gaborone & Central District:2027-03, 2027-05
```

---

## 6. Comprehensive Verification Matrix

Every feature claimed in Mokgosi has been tested and verified across all test runners:

| Component | Automated Test Suite | Passing Tests | Analyzer / Build Status |
| :--- | :--- | :--- | :--- |
| **Backend** | Pytest (`mokgosi-backend/tests/`) | **42 / 42 passed** | `py_compile` 0 errors |
| **Mobile** | Flutter Test (`mokgosi-mobile/test/`) | **21 / 21 passed** | `flutter analyze` 0 issues |
| **Dashboard** | Node Test (`mokgosi-dashboard/tests/`) | **8 / 8 passed** | `vite build` clean (2.27s) |
| **Total** | Full Repository | **71 / 71 passed** | **100% Green** |

---

## 7. Master Documentation Index

- **Product & Architecture Specification:** [`docs/ARCHITECTURE.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/ARCHITECTURE.md)
- **Threat Model & Safety Analysis:** [`docs/PRIVACY_AND_SAFETY.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/PRIVACY_AND_SAFETY.md)
- **Partner Verification Checklist:** [`docs/PARTNERS_TODO.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/PARTNERS_TODO.md)
- **Demo Walkthrough:** [`docs/DEMO_SCRIPT.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/DEMO_SCRIPT.md)
- **Fault-Tolerance Rehearsal Guide:** [`docs/REHEARSAL.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/REHEARSAL.md)
- **Setswana Localization Log:** [`docs/SETSWANA_L10N.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/docs/SETSWANA_L10N.md)
- **Progress Tracking & Acceptance Log:** [`PROGRESS.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/PROGRESS.md)
- **Project README:** [`README.md`](file:///c:/Users/araba/Desktop/Projects/Mokgosi/README.md)
