# MOKGOSI — Two-Pillar Architecture & Data-Flow Specification (v3.0)

## 1. High-Level Two-Pillar Architecture Diagram

```mermaid
flowchart TD
    subgraph Mobile["1. Mokgosi Two-Pillar Mobile App (Flutter / Android)"]
        Onboarding["Pillar Selection Onboarding<br/>(Escort | Support & Safety)"]
        Disguise["Calculator Disguise (.CalculatorAlias)<br/>Math: 7*6=42 | Safe PIN: 2580= | Duress PIN: 0852="]
        FlagSecure["Native Window Protection<br/>(FLAG_SECURE blanking recent-apps)"]
        PillarA_Mob["Pillar A: Getting Around Safely<br/>(Active Escort | 3.5g Accelerometer | 15s Check-in)"]
        PillarB_Mob["Pillar B: Support & Safety<br/>(Safe Network Max 5 | 3-Shake SOS | Evidence Vault)"]
        EvidenceMode["Survivor-Owned Evidence Vault<br/>(Silent Audio/Photo/Note | Encrypted Sandbox | Sealed Case Bundles)"]
        OfflineQ["Offline Idempotent Queue (client_event_id)<br/>+ Dual-Routing SMS Fallback (smsto:)"]
    end

    subgraph Backend["2. Mokgosi Incident, Safe Network & Evidence Engine (FastAPI)"]
        Auth["Device Auth (X-Device-Key) &<br/>Responder Auth (Supabase JWT + Rate Limit)"]
        Priority["Priority Engine<br/>SOS/Duress/Covert -> P1 | >=3.5g -> P2 | Timeout -> P3"]
        SafeNetwork["Safe Network Priority Escalation Chain<br/>(Contacts 1-5, Signed /ack/{token} One-Click Links)"]
        EvidenceService["Evidence Service & Case Bundles<br/>(Ed25519 Signed Manifests, Expiring ZIP, verify_manifest.py)"]
        Analytics["Coarse Grid Spatial Analytics<br/>(500m cells, K-Anonymity suppression < 5 incidents)"]
        Vault["Ed25519 Evidence Vault<br/>(Process-stable persistent seed)"]
    end

    subgraph Database["3. Supabase + PostGIS (RLS on All Tables & Append-Only Triggers)"]
        CoreTables["incidents | incident_locations | devices"]
        PillarBTables["trusted_contacts | incident_notifications<br/>evidence_entries | referral_partners<br/>incident_referrals | user_consents"]
        PostGIS["registered_cameras + PostGIS RPC<br/>get_authorized_nearby_cameras (150m, opt-in)"]
        Forensics["evidence_manifests & evidence_audit_logs<br/>(BEFORE UPDATE/DELETE/TRUNCATE deny triggers)"]
    end

    subgraph Dashboard["4. Two-Pillar Responder Console (React + Vite + Leaflet)"]
        PillarSwitch["Two-Pillar Switcher Tab<br/>Pillar A: Safer Communities | Pillar B: GBV Response"]
        Queue["Urgency-Sorted Incident Queue<br/>(P1 > P2 > P3, SLA Timers, Pillar Filtering)"]
        GbvCase["GbvCaseView (Pillar B)<br/>Consents upfront | Silent Duress Override Banner<br/>Escalation Timeline | Referral Handoff | Pattern Signal"]
        SaferCase["Safer Communities View (Pillar A)<br/>TacticalMap (150m PostGIS, CCTV Cones)<br/>HotspotsView (K-Anonymity Coarse Grid)"]
        Modals["CctvStreamModal (Snapshot) & EvidenceDocketModal (Ed25519 Verify)"]
    end

    Disguise -->|"Normal math"| Disguise
    Disguise -->|"Safe PIN 2580="| Onboarding
    Disguise -->|"Duress PIN 0852="| OfflineQ
    Onboarding --> PillarA_Mob
    Onboarding --> PillarB_Mob
    PillarB_Mob --> EvidenceMode
    PillarA_Mob --> OfflineQ
    PillarB_Mob --> OfflineQ
    OfflineQ -->|"HTTP POST /api/v1/incidents/trigger"| Auth
    Auth --> Priority
    Priority --> SafeNetwork
    Priority --> CoreTables
    SafeNetwork --> PillarBTables
    EvidenceMode --> EvidenceService --> Forensics
    Analytics --> SaferCase
    CoreTables -->|"Supabase Realtime (< 1s)"| Queue
    Queue --> PillarSwitch
    PillarSwitch -->|"Pillar A"| SaferCase
    PillarSwitch -->|"Pillar B"| GbvCase
    GbvCase --> Forensics
    SaferCase --> Modals
```

---

## 2. Separation of Responsibilities & Core Invariants

1. **Independent Dual-Routing (`Route 1` vs `Route 2`):**
   - Safe network trusted contact dispatch (`Route 1`) and Command Center incident recording (`Route 2`) operate on completely isolated, decoupled paths. Neither path gates, blocks, or cancels the other.
   - Even if the database fails, the trusted contact notification still fires.
2. **Strict Covert Standards (Pillar B):**
   - Covert SOS triggers (`COVERT_SOS`, `SHAKE_SOS`, `DURESS_PIN`) generate **zero sound, zero vibration, zero toast notifications, and zero on-screen alerts**.
   - Launcher label and icon display a working calculator (`.CalculatorAlias`); recent-apps task switcher is blanked via native `FLAG_SECURE`.
   - Outbound responder calls/texts are strictly blocked by system policy for covert alerts.
3. **Survivor Data Sovereignty & Evidence Mode:**
   - Evidence media is stored in an encrypted local sandbox and backed up to a private storage bucket.
   - No evidence is shared automatically with responders. The survivor explicitly selects entries to generate a signed forensic case bundle ZIP with an expiring download token (`/api/v1/evidence-bundles/{token}`).
4. **Honest Referral Handoffs:**
   - Referral partner records in `referral_partners` are strictly flagged `verified = false` until formal bilateral operational agreements are signed. Unverified numbers are never shown as callable contacts to survivors.
5. **K-Anonymity Spatial Analytics:**
   - The community analytics endpoint aggregates incidents into coarse ~500m grid cells and suppresses any cell with fewer than 5 incidents (or fewer than 10 GBV incidents) to guarantee anonymity.
6. **Ed25519 Cryptographic Integrity:**
   - All manifests are signed using persistent Ed25519 keys over canonical sorted JSON. Tampered payloads fail verification both in-app and via standalone offline Python scripts (`verify_manifest.py`).
