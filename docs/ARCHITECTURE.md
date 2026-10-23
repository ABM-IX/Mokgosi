# MOKGOSI — System Architecture & Data-Flow Specification (v2.1)

## 1. High-Level Architecture Diagram

```mermaid
flowchart TD
    subgraph Mobile["1. Mokgosi Personal Safety App (Flutter / Android)"]
        Escort["Active Escort Foreground Service<br/>(location | microphone)"]
        Sensors["MotionTelemetry (Accelerometer >= 3.5g)<br/>+ Geolocator Live GPS"]
        Checkin["15s Lock-Screen Full-Screen Intent<br/>+ Repeating Waveform Vibration"]
        PinGuard["PinGuard (Salted SHA-256)<br/>Safe (2580) | Duress (0852) | 3-Strike Duress"]
        Decoy["Covert DecoySafeScreen<br/>(pushAndRemoveUntil + PopScope blocked)"]
        OfflineQ["Offline Idempotent Queue (client_event_id)<br/>+ Device SMS Fallback (smsto:)"]
    end

    subgraph Backend["2. Mokgosi Incident & Evidence Engine (FastAPI)"]
        Auth["Device Auth (X-Device-Key) &<br/>Responder Auth (Supabase JWT + Rate Limit)"]
        Priority["Priority Engine<br/>SOS/Duress -> P1 | >=3.5g -> P2 | Timeout -> P3"]
        Route1["Route 1: Trusted Person Notifier<br/>(console | webhook | twilio, 3x retry)"]
        Route2["Route 2: Supabase Persistence<br/>+ 60s Repeat Coalescing (Upgrade-Only)"]
        Route3["Route 3: Non-Blocking Acoustic Context<br/>(DETERMINISTIC_DEMO / YAMNet Upgrade-Only)"]
        Vault["Ed25519 Evidence Vault<br/>(SHA-256 + Canonical JSON Signature)"]
    end

    subgraph Database["3. Supabase + PostGIS (RLS & Append-Only Triggers)"]
        Tables["incidents | incident_locations<br/>trusted_contacts | devices"]
        PostGIS["registered_cameras + PostGIS RPC<br/>get_authorized_nearby_cameras (150m, opt-in)"]
        Forensics["evidence_manifests & evidence_audit_logs<br/>(BEFORE UPDATE/DELETE/TRUNCATE deny triggers)"]
    end

    subgraph Dashboard["4. Responder Command Center (React + Vite + Leaflet)"]
        Queue["Priority-Sorted Queue (P1 > P2 > P3)<br/>+ Live SLA Timers & Audible P1 Alert"]
        DuressUI["Covert Duress Warning Banner &<br/>GBV Referral Protocol"]
        Map["TacticalMap (Live Breadcrumbs,<br/>150m Radius & Camera FOV Cones)"]
        Modals["CctvStreamModal (Snapshot Capture) &<br/>EvidenceDocketModal (Live Ed25519 Verify)"]
    end

    Escort --> Sensors --> Checkin --> PinGuard
    PinGuard -->|"0852 or 3 wrong PINs"| Decoy
    PinGuard -->|"Trigger SOS / Duress / Timeout"| OfflineQ
    OfflineQ -->|"HTTP POST /api/v1/incidents/trigger"| Auth
    Auth --> Priority
    Priority -->|"Independent Path"| Route1
    Priority -->|"Independent Path"| Route2
    Route2 --> Tables
    Route2 --> PostGIS
    Route3 --> Vault --> Forensics
    Tables -->|"Supabase Realtime (< 1s)"| Queue
    Queue --> DuressUI
    Queue --> Map
    Forensics --> Modals
```

---

## 2. Separation of Responsibilities & Core Invariants

1. **Independent Dual-Routing (`Route 1` vs `Route 2`):**
   - `trigger_incident` in [`mokgosi-backend/main.py`](../mokgosi-backend/main.py) schedules Trusted Person notification (`Route 1`) even if Supabase is unreachable (`HTTP 202 ACCEPTED`, `persistence_state: "UNAVAILABLE"`) or if the `incidents` insert fails (`persistence_state: "FAILED"`).
   - Conversely, if the external SMS/webhook provider fails after 3 retries (`Route 1`), the incident remains active in Supabase (`Route 2`) and `TRUSTED_CONTACT_FAILED` is recorded in `evidence_audit_logs`.
   - PostGIS camera matching (`get_authorized_nearby_cameras`) and audit log inserts are best-effort and never roll back or fail an active incident.
2. **Idempotency & 60-Second Coalescing:**
   - Every mobile alert generates a UUID v4 `client_event_id` persisted in the mobile offline queue before transmission.
   - Retrying the same `client_event_id` returns the existing incident (`200 OK`).
   - Subsequent triggers from the same `user_id` within 60 seconds coalesce onto the open incident (`REPEAT_TRIGGER`), upgrading priority if the new trigger is higher and never downgrading.
3. **Strict Responder Lifecycle State Machine:**
   - Enforces `CREATED → ACKNOWLEDGED → ASSIGNED → DISPATCHED → RESOLVED` (`409 Conflict` on any skipped or backward transition) and records `acknowledged_by/at`, `assigned_to/at`, `dispatched_at`, and `resolved_at` using the verified Supabase Auth responder identity.
4. **Tamper-Evident Cryptographic Evidence Vault:**
   - Requires a persistent 32-byte `ED25519_PRIVATE_KEY_SEED` at process startup (refusing to generate ephemeral keys).
   - Every consenting audio clip (`AUDIO_CONTEXT_CLIP`) and authorized camera frame (`AUTHORIZED_CCTV_FRAME`) is hashed (`SHA-256`), signed (`Ed25519`) over canonical sorted JSON, protected by PostgreSQL append-only triggers, and verifiable both in-app (`/api/v1/evidence/verify`) and offline (`python verify_manifest.py`).

