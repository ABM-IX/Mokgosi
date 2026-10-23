# MOKGOSI — Stage 6 Live Fault-Tolerance Rehearsal Checklist

> [!IMPORTANT]
> Every scenario in this checklist verifies the core engineering invariant:
> **The safety response must work even when AI, the database, or the SMS provider fails.**
> Trusted-person alerts and Command Center incidents are independent paths; AI only raises priority and never gates, downgrades, or cancels an alert; and the UI never claims an alert was sent unless the server returned HTTP 2xx.

---

## 1. Automated Fault-Tolerance Scenarios (`pytest` + `flutter test`)

Run the automated rehearsal suite before every live demo:

```powershell
# Backend fault-tolerance & security suite (24 tests)
cd mokgosi-backend
.\.venv\Scripts\python.exe -m pytest -v

# Mobile offline queue, duress, & sensor telemetry suite (6 tests)
cd ..\mokgosi-mobile
flutter test

# Dashboard component & SLA sorting suite (3 tests)
cd ..\mokgosi-dashboard
npm test
```

| Scenario | Automated Test | Expected & Verified Outcome |
| :--- | :--- | :--- |
| **1. Supabase / DB Down** | `test_database_failure_does_not_suppress_trusted_person_route` & `test_incident_insert_failure_still_queues_trusted_person_dispatch` | Backend still queues Trusted Person dispatch (`Route 1`), returns HTTP `202 ACCEPTED` with `incident_persisted: false` and `persistence_state: "UNAVAILABLE"` / `"FAILED"`. Mobile UI reports honest unpersisted state. |
| **2. PostGIS Camera RPC or Audit Log Failure** | `test_camera_and_audit_failures_do_not_undo_incident` | Incident row remains persisted (`200 OK`), `authorized_cameras: []` returned, and Trusted Person alert still fires. |
| **3. SMS / Notifier Provider Offline** | `test_notifier_failure_logs_failure_and_keeps_incident` & `test_trusted_notifier_retries_three_times` | Retries 3 times with exponential backoff, records `TRUSTED_CONTACT_FAILED` in `evidence_audit_logs`, and keeps Command Center incident active. |
| **4. 10 Rapid Duplicate SOS Taps** | `test_ten_rapid_duplicate_sos_taps_create_single_incident` & `test_repeat_within_60_seconds_coalesces_and_only_raises_priority` | Identical `client_event_id` returns the existing incident (`200 OK`, 1 row). Distinct triggers from the same user within 60s coalesce onto the open incident (`REPEAT_TRIGGER` logged) and only upgrade priority (`P3 -> P1`). |
| **5. AI Acoustic Worker Killed / Offline** | `test_acoustic_demo_only_upgrades_priority_and_worker_failure_is_neutral` | Returns `status: "UNAVAILABLE"`, leaves incident status and priority untouched, and still records the signed audio evidence manifest if audio bytes were uploaded. |
| **6. Wi-Fi / Airplane Mode Offline Queue & SMS Fallback** | `Offline queue persists client_event_id, fires SMS fallback, and deduplicates on flush` (`widget_test.dart`) | Alert is queued locally with its original `client_event_id` and `source_timestamp_utc`; UI shows `"Queued — no signal..."` (never a false "sent" message); device SMS fallback fires; when network returns, `flushOfflineQueue()` delivers 1 incident row. |
| **7. Microphone Permission Denied** | `uploadConsentingAudioClip` (`incident_api.dart`) | `EXPLICIT_SOS`, `DURESS_PIN`, and `MISSED_CHECKIN` fire immediately before any audio recording attempt; denied mic permission simply skips Route 3 audio upload. |

---

## 2. Live Manual Rehearsal Steps (Emulator + Physical Device Notes)

### A. Airplane Mode / Wi-Fi Cut Mid-Escort
1. Open the Mokgosi app and tap the **beaker icon** (`Demo & Rehearsal Controls`) in the top bar.
2. Enable **Simulate Airplane / Offline Mode** (or disable Wi-Fi/cellular data on the device).
3. Tap **SEND SOS**.
4. **Verify:**
   - Status text displays: `Queued — no signal. Will send automatically when online. Device SMS fallback opened.`
   - Offline queue badge appears: `Offline queue: 1 alert(s) waiting for signal.`
   - On Android, the SMS composer intent (`smsto:`) opens pre-filled with the Google Maps coordinate link (`https://www.google.com/maps?q=-24.656,25.909`).
5. Disable **Simulate Airplane / Offline Mode** (or restore Wi-Fi).
6. **Verify:** The queued alert flushes automatically using the same `client_event_id`, creating **one** `P1_CRITICAL` row on the Command Center dashboard.

### B. Backend Restart Mid-Escort
1. Start a 30-second escort on the mobile app (`ESCORT ACTIVE`).
2. Stop the FastAPI `uvicorn` server (`Ctrl+C`) while the countdown is running.
3. Let the 15-second check-in expire (`MISSED_CHECKIN`).
4. **Verify:** The mobile app does **not** crash or falsely claim delivery; it queues the `MISSED_CHECKIN` event in the offline retry queue.
5. Restart `uvicorn main:app --env-file .env --reload`.
6. Tap **RETRY NOW** (or wait 5 seconds for automatic retry flush).
7. **Verify:** The queued `MISSED_CHECKIN` incident is delivered with its original `source_timestamp_utc` preserved as `source_capture_utc`.

### C. Physical Device vs Emulator Verification Matrix
- **Verified on Android Emulator + Automated Tests:**
  - Android project build (`app-debug.apk`), `EscortForegroundService` registration (`foregroundServiceType="location|microphone"`), lock-screen `fullScreenIntent` notification channel creation, PIN hashing & 3-strike covert duress, `PopScope(canPop: false)` decoy screen, $\ge 3.5g$ simulated impact $\rightarrow$ `P2_HIGH`, and offline queue deduplication.
- **Unverified (Requires Physical Android Phone & Live Carrier):**
  - OEM lock-screen wake over hardware keyguard (`showWhenLocked` / `turnScreenOn` under vendor battery savers such as Samsung OneUI / Xiaomi MIUI).
  - Physical accelerometer drop/impact threshold calibration in pocket/handbag.
  - Real Twilio outbound SMS delivery to a `+267` Botswana mobile number (Mascom / Orange / BTC) and real cellular SMS transmission.

