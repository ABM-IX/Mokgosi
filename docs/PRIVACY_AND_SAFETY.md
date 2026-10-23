# MOKGOSI — Privacy, Threat Model & Survivor Safety Specification

## 1. Threat Model (GBV & Personal Safety Context)

In Gender-Based Violence (GBV) and intimate-partner coercion scenarios, a standard "panic button" app can increase danger if an abuser has physical access to the survivor's phone, watches the screen during a check-in, or intercepts incoming notifications.

| Threat Vector | Risk to Survivor | Mokgosi Mitigation | Residual Limitations (Honest Scope) |
| :--- | :--- | :--- | :--- |
| **Shoulder-surfing & Coerced Cancellation** | Assailant forces the user to enter their PIN to cancel a safety check-in. | **Covert Duress PIN (`0852`) & 3-Strike Escalation:** Entering the Duress PIN (or 3 consecutive wrong PINs) immediately stops vibration, transitions via `pushAndRemoveUntil` + `PopScope(canPop: false)` to a neutral `"Journey Completed — Location sharing turned off"` decoy screen, and silently dispatches a `P1_CRITICAL` alert while continuing background location updates. | If an assailant force-closes the app from Android System Settings or powers off the phone hardware, background telemetry stops after the initial alert packet. |
| **Exposing PIN Hints or Alert Status on Screen** | On-screen text reveals that a silent duress alert was sent or shows the Duress PIN. | Default UI hides all PIN hints. After Duress PIN entry, no status message, toast, or back-navigation path ever mentions duress or SOS. | In `DEMO_MODE`, rehearsal controls are accessible via the top-bar beaker icon for hackathon judges; keep `MOKGOSI_DEMO_MODE=false` in production builds. |
| **Responder Callback Exposing Covert Duress** | A well-meaning dispatcher calls or texts the survivor’s phone during a covert duress incident, alerting the abuser. | Dashboard renders a high-visibility red banner on `DURESS_PIN` and `GBV_DOMESTIC` incidents: **`⚠️ SILENT DURESS — do NOT call or message the user`**. | Requires responder SOP training and adherence. |
| **Unauthorized Access to Victim Locations or CCTV** | Anonymous clients using the public Supabase `anon` key read live coordinates or camera stream URLs. | Row Level Security (`ENABLE ROW LEVEL SECURITY`) is enforced on every table (`incidents`, `incident_locations`, `registered_cameras`, `evidence_manifests`, `evidence_audit_logs`, `trusted_contacts`, `devices`). `anon` has all privileges revoked; `get_authorized_nearby_cameras` RPC is revoked from `PUBLIC` and `anon`. | Requires Supabase Auth responder role assignment (`app_metadata.role = "responder"`) in production deployments. |
| **Evidence Tampering or Spoofed Operator Logs** | Post-incident modification of audio/video hashes or forging `responder_id` in audit logs. | Backend derives `responder_id` strictly from the verified Supabase JWT token, signs canonical JSON manifests with a persistent process-stable **Ed25519** private key, and enforces PostgreSQL `BEFORE UPDATE OR DELETE OR TRUNCATE` triggers on `evidence_manifests` and `evidence_audit_logs`. | Does not replace formal chain-of-custody hardware HSMs; legal admissibility and Botswana Data Protection Act compliance require formal legal review (`TODO: legal & forensic certification review`). |
| **Unconsented Surveillance / Camera Misuse** | Continuous background audio recording or querying unauthorized private cameras. | **Strict Opt-In & 150m Radius Bound:** Audio context (`Route 3`) requires an explicit survivor consent toggle prior to escort start and records only a 15-second post-trigger clip. PostGIS queries only cameras where `is_authorized = TRUE`, `connection_status = 'ONLINE'`, and distance $\le 150\text{ m}$. Every view, stream open, and snapshot writes to `evidence_audit_logs`. | Seeded Gaborone CBD camera rows are **DEMO ONLY** entries pointing to `http://localhost:8080/video`. |

---

## 2. Data Minimisation, Retention & Survivor Control

1. **Explicit Consent Controls:**
   - Before starting an escort, the survivor controls whether live GPS breadcrumbs are shared and whether a 15-second post-alert acoustic triage clip may be uploaded.
   - Declining microphone permission or audio consent **never** blocks or delays `Route 1` (Trusted Person) or `Route 2` (Command Center).
2. **Retention Policy:**
   - Registered opt-in cameras declare `retention_policy_hours` (default **72 hours**).
   - Consenting 15-second acoustic clips are scoped to active incident triage (72-hour retention policy target).
3. **Survivor Data Deletion Path (`DELETE /api/v1/users/{user_id}/data`):**
   - Survivors can clear their local profile, salted PIN hashes, offline queue, and mutable contact preferences from the **Safety & Trusted Contact Setup** screen (`Delete My Personal Data`), while append-only forensic manifests (`evidence_manifests` and `evidence_audit_logs`) remain sealed to preserve evidentiary integrity.
4. **Partner & Referral Placeholders:**
   - No phone numbers, agency partnerships, or regulatory compliance claims are invented in the codebase. Responder referral cards explicitly carry `TODO: confirm with Botswana Police Service GBV desk / Department of Gender Affairs / NGO partners` placeholders until verified with official stakeholders.

