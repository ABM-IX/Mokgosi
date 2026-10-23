# MOKGOSI — Coding Agent Brief: Close the Gap Between Code and Spec

You are working on **MOKGOSI — Personal Safety & Response Network** ("Your call for help. A connected response."), our entry to the **FNB hackathon, theme: Safer Communities & Gender-Based Violence (GBV) Response**. The repo has three apps plus a schema: `mokgosi-backend/` (FastAPI), `mokgosi-mobile/` (Flutter), `mokgosi-dashboard/` (React + Vite + Leaflet), `database/schema.sql` (Supabase + PostGIS). The master spec is `MOKGOSI Master System Architecture v2.0` (attached/in repo). Read the spec and every source file before changing anything.

## 0. The non-negotiables (every change is judged against these)

1. **Engineering invariant: the safety response must work even when the AI fails.** AI only adds context or *raises* priority. It never delays, gates, downgrades, hides, or cancels an alert.
2. **Simultaneous dual-routing.** On SOS / duress / missed check-in, the Trusted Person alert and the Command Center incident are *independent* paths. Failure of one (database down, camera RPC error, audit insert error, SMS provider error) must never stop the other.
3. **A false "alert sent" message is worse than no message.** The UI may only claim success after the server returned 2xx. Otherwise queue and retry, and show the honest state.
4. **Duress must be covert.** After the Duress PIN, nothing on the phone may reveal that an alert was sent (no text, no navigation back to a screen that says so, no visible PIN hints).
5. **Be honest about what is real vs demo.** Anything simulated is labelled `DEMO` in the data and in the UI. We must never claim YAMNet, SMS delivery, or CCTV integration that isn't actually running.
6. **Scope discipline.** Hackathon demo first, production-shaped second. Do not add features outside this brief. Keep the 6 build gates in order; do not start a phase until the previous phase's acceptance tests pass. Report results after each phase.

## 1. Audit results you must fix (verified against the code)

I ran compile/build checks. Verified facts first, then the rest of the gaps.

### Verified defects
- **`mokgosi-mobile/lib/main.dart` does not compile.** It has 21 `{` and 22 `}` (stray closing brace on the last line). Also verify `AppBar(subtitle: …)`; I don't believe `AppBar` has a `subtitle` parameter in stable Flutter. Replace it with a `Column` title if the analyzer rejects it.
- **The mobile project is not runnable as shipped.** Only `AndroidManifest.xml` exists under `android/`. There is no Gradle config, `MainActivity`, or `res/` styles that the manifest references (`@style/LaunchTheme`, `@mipmap/ic_launcher`). Run `flutter create --platforms=android --project-name mokgosi_mobile .` inside `mokgosi-mobile/`, then re-apply our manifest changes on top of the generated one. Update the README accordingly.
- **Evidence signing key changes on every call when `ED25519_PRIVATE_KEY_SEED` is unset** (`evidence_vault._key()` calls `os.urandom` each time). Confirmed: two manifests produced two different public keys, so no signature can ever be verified. This silently breaks the whole "tamper-evident evidence" claim.
- Dashboard builds cleanly (`npm run build` passes). Backend compiles. Neither has any tests.

### Backend gaps (violations of invariants 1–3)
1. `trigger_incident` raises 502 if *any* step fails (camera RPC, audit insert) **after** the incident row was already inserted, and the trusted-person dispatch is only scheduled at the very end. DB trouble therefore means **no Trusted Person alert at all**, and the phone will retry and create duplicates. Restructure: start the trusted-person dispatch first/independently, make the incident insert the only hard dependency for the Command Center path, and make camera lookup + audit logging best-effort (log and continue, return `authorized_cameras: []` on failure).
2. If Supabase is unconfigured/unreachable the endpoint returns 503/502 and **nothing is notified**. Trusted-person dispatch must still run. Also create the Supabase client once (cached), not per request.
3. `trusted_notifier.dispatch` only prints or posts to an optional webhook. It writes **no audit log** (`TRUSTED_CONTACT_ALERTED` was in the spec), has no retry, swallows webhook failures silently, and has no real SMS provider. Implement a provider interface with: `console` (demo default), `webhook`, and one real SMS adapter (Twilio or Africa's Talking, chosen by env; verify Botswana coverage) behind `NOTIFIER_PROVIDER`. Retry with backoff (3 attempts), and write `TRUSTED_CONTACT_ALERTED` or `TRUSTED_CONTACT_FAILED` to `evidence_audit_logs` with the outcome. Validate phone numbers as E.164.
4. **No idempotency.** Duplicate SOS taps (Stage 6) create duplicate incidents. Add `client_event_id` (UUID from the phone) with a unique index; a repeat returns the existing incident (HTTP 200, same body). Also coalesce: same `user_id` + same open incident within 60 s → append a `REPEAT_TRIGGER` audit entry instead of a new row, but upgrade priority if the new trigger is higher.
5. **No authentication anywhere.** Anyone can POST triggers, PATCH an incident to `RESOLVED`, or call the acoustic endpoint. Add: a device token (`X-Device-Key`, env-configured, per-device for the demo) on `/trigger` and `/location`; a responder JWT (Supabase Auth) on `/lifecycle`, `/audit`, `/acoustic-context`; `CORS_ORIGINS` restricted by default (not `*`); simple per-IP/per-device rate limiting. `responder_id` must come from the verified token, **never from the request body** (today the audit trail can be spoofed).
6. **Lifecycle has no state machine.** Enforce `CREATED → ACKNOWLEDGED → ASSIGNED → DISPATCHED → RESOLVED` (no skipping backwards; RESOLVED is terminal; return 409 on illegal transitions). Add `assigned_to/at`, `dispatched_at`, `resolved_at` columns so SLA metrics are real.
7. `source_timestamp_utc` is accepted but ignored. Store it as `source_capture_utc` on the incident (needed for offline-queued alerts) and use it in manifests.
8. **No live location.** Only one lat/lng ever exists; the spec's "live Google Maps coordinate link" is just a snapshot. Add `POST /api/v1/incidents/{id}/location` (appends to a new `incident_locations` table) and have the dashboard/map follow the latest point. The trusted-person SMS should link to a small public tracking page or at least the latest coordinates.
9. **Acoustic endpoint:** it never looks at the uploaded audio (profile comes from a form field), and the audio isn't stored, so the hash proves nothing retrievable. Required: (a) gate the `simulated_profile` path behind `DEMO_MODE=true`; (b) real path: classify uploaded audio with YAMNet (TFLite or TF Hub) in a background worker **with a hard timeout and full try/except**, falling back to `status: "UNAVAILABLE"` and *no change to the incident*; (c) upgrade-only logic: P3→P2/P1, P2→P1, never downgrade; (d) store the clip in a Supabase Storage bucket and put the path in the manifest; (e) `model` must say `DETERMINISTIC_DEMO` vs `YAMNet-v1` truthfully. If real YAMNet is not feasible in the time, keep deterministic mode but label it clearly in the dashboard.
10. **No CCTV snapshot manifest.** Stage 5 requires every audio clip *or snapshot* to be hashed and signed. Add `POST /api/v1/incidents/{id}/cctv-snapshot` (server fetches one frame from the authorized camera's `stream_url` with a short timeout, signs it as `AUTHORIZED_CCTV_FRAME`, and logs `CCTV_SNAPSHOT_CAPTURED`). Must only work for cameras returned by `get_authorized_nearby_cameras` for that incident.
11. **Evidence vault:** require `ED25519_PRIVATE_KEY_SEED` (fail fast at startup with a clear message, plus a `scripts/gen_key.py`), compute the key once at import, add `GET /api/v1/evidence/public-key` and `POST /api/v1/evidence/verify` (recompute canonical JSON + check signature), and add a standalone `verify_manifest.py` a judge can run offline.
12. **Audit completeness:** spec says every view, stream open, and status change is logged. Only status changes are. Add `POST /api/v1/incidents/{id}/audit` for `VIEW_INCIDENT`, `OPEN_CCTV_STREAM`, `VIEW_EVIDENCE` (actor from JWT).
13. Remove unused `numpy` or actually use it; add `pytest` + `httpx` and a real test suite (see Phase 6). `test_pipeline.py` currently only smoke-tests Stage 1.

### Database gaps (`database/schema.sql`)
- **No Row Level Security.** The dashboard uses the anon key to read `incidents`, `evidence_*`, and the camera RPC (which returns `stream_url`). For a GBV product, that means **anyone with the anon key can read victims' live locations and camera URLs.** Enable RLS on every table; policies: `authenticated` responders may `SELECT`; only the service role writes. Revoke anon execute on the camera RPC.
- **`evidence_audit_logs` is not append-only** despite being described that way. Add a trigger that raises on `UPDATE`/`DELETE`; same for `evidence_manifests`.
- Add indexes: `GIST(location)` on both spatial tables, `incidents(created_at DESC)`, `incidents(priority, status)`, unique `incidents(client_event_id)`.
- Add tables: `trusted_contacts` (user_id, name, phone E.164, verified), `incident_locations`, optionally `devices`. Add columns: `client_event_id`, `source_capture_utc`, `assigned_to/at`, `dispatched_at`, `resolved_at`, `category` (default `PERSONAL_SAFETY`, allow `GBV_DOMESTIC`), `media_storage_path` on manifests.
- Keep the seed cameras and the idempotent `DO $$` pattern. Make migrations re-runnable.

### Mobile gaps (this is the heart of the product and the weakest part)
Current state: a single 27-line `main.dart` with a Dart `Timer`, a text field for the PIN, and one hard-coded location. `sensors_plus`, `geolocator`, and `flutter_local_notifications` are in `pubspec.yaml` but **never imported anywhere.**

1. **No Android foreground service.** The manifest requests permissions but declares no `<service>`. The escort timer is a UI `Timer`, so it dies when the screen locks or the app is backgrounded, which is exactly when a victim needs it. Implement a real foreground service (`flutter_foreground_task` or `flutter_background_service`) with `foregroundServiceType="location|microphone"`, a persistent notification ("Mokgosi Escort Active — Monitoring route & motion sensors."), and the timer + sensor listeners running inside it. Handle Android 13+ notification permission and Android 14 foreground-service-type permissions. Microphone type must only be used after the user granted RECORD_AUDIO and consented.
2. **No lock-screen check-in.** Needs a full-screen-intent notification (high-importance channel, `fullScreenIntent: true`), `android:showWhenLocked="true"` and `android:turnScreenOn="true"` on `MainActivity`, a runtime check for `USE_FULL_SCREEN_INTENT` on Android 14+, and an urgent *vibration pattern* (not a single `HapticFeedback.vibrate()`), repeating through the 15 s window.
3. **No accelerometer / impact detection.** Implement `motion_telemetry.dart`: magnitude of the accelerometer vector / 9.81 ≥ 3.5 g starts the 15 s check-in with `MOTION_IMPACT`, tracking peak g and sending it as `impact_g_force`. Include a "Simulate impact" button behind a `demoMode` flag so it can be demonstrated without throwing a phone. A missed check-in that followed an impact must send the peak g so the server assigns `P2_HIGH`. Route-stagnation detection is a stretch goal (document if skipped).
4. **No real GPS.** `lat/lng` are hard-coded to -24.6560, 25.9090. Use `geolocator` with permission handling, send the real fix, and stream updates to `/location` while an alert is active. Keep a demo override that pins to the Gaborone CBD cameras.
5. **Duress leaks.** (a) `_send` sets the home screen message to "DURESS_PIN alert sent…", and the decoy's "Done" button pops back to that screen. (b) The home screen shows "Demo PINs: safe 2580 · duress 0852" to anyone looking over the shoulder. (c) The decoy is pushed, not replaced, so the back button returns to the real UI. Fix: `pushAndRemoveUntil` to the decoy, block back (`PopScope`), show a neutral completed-journey UI only, **keep silently sending location and keep the escort/service alive** in the background, show no duress-related text anywhere, and hide the demo-PIN legend behind `demoMode`. Wrong-PIN handling must not cancel anything; 3 consecutive wrong PINs should be treated as duress.
6. **False assurance and no offline queue.** `IncidentApi.trigger` doesn't check the status code, swallows exceptions, and the UI then says "alert sent". Implement the spec's offline retry queue: persist unsent events (`sqflite` or `shared_preferences`), generate `client_event_id` per event, retry with exponential backoff and on connectivity change (`connectivity_plus`), keep the true state visible only on non-duress screens ("Sending… / Queued — no signal / Delivered"). **Fallback SMS:** if no data connection, open/send an SMS with the coordinates to the Trusted Person via the device (document Android SMS permission limits; sideloaded demo build is fine). Never block the alert on audio, AI, or location-accuracy waiting; send the last known fix immediately and refine later.
7. **No Route 3 audio.** The phone never records or uploads the 15 s consenting clip. Add an explicit consent toggle at escort start, record 15 s after an alert is sent (`record` package), upload to `/acoustic-context` in the background. Denied permission or upload failure must not affect the alert.
8. **No Trusted Person setup.** The contact is hard-coded in the UI and in `IncidentApi`. Add an onboarding/settings screen: name, phone (E.164 validation), Safe PIN, Duress PIN (must differ, 4 digits), escort duration. Store PINs hashed (salted) in `flutter_secure_storage`; keep `2580`/`0852` only as demo defaults. Persist the active escort session so it survives app kill/reboot where feasible.
9. **Escort lifecycle bugs.** `_active` is never set back to `false`, so there is no way to end an escort. Add "I'm home safe — End escort" (requires Safe PIN). The `+5 MINUTES` button passes the remaining *check-in* seconds into `_count` and leaves `_checking` true; it should resolve the check-in, set `_checking=false`, and extend the **escort** timer by 5 min (shorten to 30 s in demo). The Safe PIN currently restarts the 30 s demo timer unconditionally; make "continue vs end" explicit.
10. **Structure.** Split `main.dart` into the spec layout: `screens/escort_home.dart`, `screens/checkin_prompt.dart`, `screens/decoy_safe_screen.dart`, `services/notification_guard.dart`, `services/motion_telemetry.dart`, `services/incident_api.dart`, `config/mokgosi_config.dart`. A single state-management approach (Riverpod or Provider) is fine. Move the duress/safe PIN comparison out of widgets into a small unit-tested class. `lib/` should pass `flutter analyze` with zero errors.

### Dashboard gaps
Current: one 20-line `App.jsx` with dense one-liners; works, but is far from the spec'd Command Center.
1. Split into spec components: `HeaderBar`, `IncidentQueue`, `TacticalMap`, `CctvStreamModal`, `EvidenceDocketModal` (+ `lib/api.js`, `lib/supabaseClient.js`).
2. **Queue ordering and urgency:** sort by priority (P1 first) then age; per-card live SLA timer (time since `created_at`, turns red if unacknowledged > configurable threshold); header SLA metrics (open P1 count, median time-to-acknowledge, from the new timestamp columns); audible + visual alert on new P1 (needs a user gesture to enable audio); auto-select a new P1 on INSERT.
3. **DURESS banner:** for `DURESS_PIN` incidents show a prominent warning — "SILENT DURESS — do NOT call or message the user" — and a different card style.
4. **Lifecycle UI:** add the missing **Assign** step, enable only valid next actions (mirrors the backend state machine), show who acknowledged/assigned/dispatched. Resolved incidents move to a "Resolved" tab.
5. **Auth:** responder sign-in with Supabase Auth; operator ID from the session, not the hard-coded `DISP_GABORONE_01`. Show the real operator in the header.
6. **TacticalMap:** draw camera **FOV cones** (azimuth + fov) not just markers; follow live `incident_locations` with a breadcrumb trail; fix Leaflet's default marker icons under Vite (known broken-icon issue); distinct pulsing marker per priority.
7. **CctvStreamModal:** embed the authorized stream (MJPEG `<img>` or `<video>`) in a modal instead of opening a new tab, handle failure ("stream unavailable — signed snapshot still available"), add "Capture signed snapshot" button calling `/cctv-snapshot`, and call `/audit` with `OPEN_CCTV_STREAM`. Call `VIEW_INCIDENT`/`VIEW_EVIDENCE` audit on selection/open.
8. **EvidenceDocketModal:** show full SHA-256, signature, key ID, capture vs server-receipt time, and a **"Verify signature" button** that calls `/evidence/verify` (or verifies in-browser with WebCrypto/tweetnacl) and shows ✓/✗. This is our best live-demo moment for "tamper-evident evidence"; make it work.
9. **AI context honesty:** show `DEMO` vs `YAMNet` clearly; show `UNAVAILABLE` (not an error) when the worker is offline; the demo-profile buttons render only when `VITE_DEMO_MODE=true`.
10. Subscribe to Realtime for `evidence_manifests` and `evidence_audit_logs` for the selected incident rather than re-fetching everything on each incident change; handle INSERT/UPDATE payloads incrementally. Realtime latency from POST to card must be demonstrably < 1 s; log it.
11. Add Tailwind only if it's quick; otherwise keep the CSS, but make the layout readable on a projector (large type for P1, high contrast).

### GBV-theme alignment (we are entering the Safer Communities & GBV Response track; the code currently reads as a generic panic button)
Keep these small and demo-able:
- `category` on incidents (`PERSONAL_SAFETY` | `GBV_DOMESTIC`), selectable at escort start ("I feel unsafe at home / with a partner"), shown on the dashboard.
- Covert-by-default design: optional app disguise (neutral launcher label and the decoy), no sound on duress, nothing in notification text that mentions violence.
- Survivor consent and data minimisation: explicit consent screen for location/audio, a retention note (cameras already have `retention_policy_hours`), and a "delete my data" path (document if only stubbed).
- A configurable list of referral resources shown to responders (placeholder entries in config, **do not invent phone numbers**; leave `TODO: confirm with Botswana Police Service GBV desk / Gender Affairs / NGO partners`).
- A short `docs/PRIVACY_AND_SAFETY.md`: threat model (abuser has phone access, SMS interception, camera misuse), what we mitigate, what we don't, and the camera-consent rules (`is_authorized` only, owner opt-in).

## 2. Build order & acceptance tests (do not skip ahead)

**Phase 0: It builds.** Fix the Dart syntax error and scaffold the Android project. *Pass:* `flutter analyze` has 0 errors, `flutter run` launches on an emulator, `npm run build` and `python -m py_compile` still pass.

**Phase 1: Backend invariant & security (Stage 1 hardened).**
*Pass (pytest, using a fake/mocked Supabase client):*
- SOS with Supabase raising an exception still calls the notifier and returns a response that states the incident persistence state honestly.
- Camera RPC failure → incident still created, `authorized_cameras: []`.
- Notifier failure → incident still created, `TRUSTED_CONTACT_FAILED` logged.
- Same `client_event_id` twice → one incident row.
- Priority table: SOS/DURESS→P1, MOTION_IMPACT→P2, MISSED_CHECKIN→P3, MISSED_CHECKIN with ≥3.5 g→P2.
- Acoustic: DISTRESSED upgrades P3→P1; CONVERSATION and SILENT never downgrade or hide; worker exception leaves the incident unchanged.
- Illegal lifecycle transition → 409; request without a valid token → 401.
- Two manifests signed in one process verify against the same public key; tampering a byte of the payload fails verification.

**Phase 2: Mobile escort & duress (Stage 2).** *Pass (on a real Android device if possible):*
- Start a 30 s escort, **lock the screen**, and the full-screen check-in appears with a vibration pattern.
- `2580` resolves cleanly; `0852` shows the decoy, back button does nothing, no trace of the alert on any screen, and a `P1_CRITICAL` row appears.
- 15 s timeout → `P3_VERIFY`; Simulate impact ≥ 3.5 g then timeout → `P2_HIGH`.
- Airplane mode on, trigger SOS → queued, then delivered automatically (same `client_event_id`, one row) when the network returns; SMS fallback fired.
- Deny mic permission → alert still sent. Real GPS coordinates are sent.

**Phase 3: Dashboard Realtime & SLA (Stage 3).** *Pass:* alert from phone appears < 1 s with sound; P1 sorts to top; Acknowledge → Assign → Dispatch → Resolve update live, each written to `evidence_audit_logs` with the **authenticated** operator ID; illegal buttons disabled; DURESS banner visible.

**Phase 4: Acoustic AI context (Stage 4).** *Pass:* distress clip upgrades P3→P1 with tags; conversation clip attaches tags without hiding/deleting; worker offline → `UNAVAILABLE`, incident unaffected; labels truthful.

**Phase 5: Evidence & controlled CCTV (Stage 5).** *Pass:* every audio clip and CCTV snapshot yields SHA-256 + Ed25519 manifest; dashboard shows full hashes; "Verify signature" returns ✓ and a tampered copy returns ✗; snapshot refused for a camera outside the 150 m/authorized set; views and stream opens appear in the audit trail.

**Phase 6: Fault-tolerance rehearsal (Stage 6).** Automate what can be automated and write `docs/REHEARSAL.md` for the rest: Wi-Fi off, mic denied, AI worker killed, Supabase down, SMS provider failing, 10 rapid duplicate SOS taps, backend restart mid-escort. *Pass:* core SOS/duress alerts and the trusted-person message still go out in each scenario, and no scenario produces a false "sent" message.

**Phase 7: GBV alignment & pitch readiness.** Implement the GBV-theme items above; update `README.md` (accurate run steps incl. `flutter create`, env vars, demo vs real matrix); add `docs/DEMO_SCRIPT.md` (a 4–5 minute walkthrough: escort → duress → dashboard → CCTV → signed evidence verify → fault-tolerance moment) and `docs/ARCHITECTURE.md` with the flow diagram.

## 3. Ground rules for how you work
- Work phase by phase. At the end of each phase output: what changed (files), the commands you ran, the test output, and anything you could **not** verify (e.g., real-device behaviour, SMS delivery) stated plainly. Do not claim a device behaviour you didn't test.
- No secrets in the repo. Update every `.env.example`. Never commit the Ed25519 seed or service keys. Service-role key lives only in the backend.
- Keep `DEMO_MODE` explicit and off by default in anything that looks like production config. Demo PINs/profiles/overrides only appear when it is on.
- Prefer small, readable files over dense one-liners. Add docstrings to anything that affects safety behaviour.
- If a requirement is ambiguous or conflicts with the invariants above, the invariants win; ask me only when the choice would change the demo story.
- Do not invent real phone numbers, organisation endorsements, partner names, or claims of Botswana Data Protection Act compliance. Where facts are needed, leave a clearly marked TODO.

Start with Phase 0 and report back before continuing.