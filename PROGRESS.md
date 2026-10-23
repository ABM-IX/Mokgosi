# MOKGOSI Build Progress

## Phase Status Summary
- **Phase 0 (It builds):** DONE
- **Phase 1 (Backend invariant & security):** DONE (24/24 pytest tests passing)
- **Phase 2 (Mobile escort & duress):** IN PROGRESS (Next up)
- **Phase 3 (Dashboard Realtime & SLA):** PENDING
- **Phase 4 (Acoustic AI context):** PARTIAL (Backend done; mobile consenting 15s audio upload & dashboard UI pending)
- **Phase 5 (Evidence & controlled CCTV):** PARTIAL (Backend `/cctv-snapshot` & `/evidence/verify` done; dashboard modals pending)
- **Phase 6 (Fault-tolerance rehearsal):** PARTIAL (Backend tests done; mobile offline queue & `docs/REHEARSAL.md` pending)
- **Phase 7 (GBV alignment & pitch readiness):** PENDING

## What Is Verified
- `mokgosi-backend`: `.\.venv\Scripts\python.exe -m py_compile` and `.\.venv\Scripts\python.exe -m pytest -v` (24 passed).
- `mokgosi-mobile`: `flutter analyze` (0 issues), `flutter test` (passed), `flutter build apk --debug` (built `app-debug.apk`).
- `mokgosi-dashboard`: `npm run build` passes.

## What Is Unverified
- Physical Android device lock-screen full-screen intent, foreground service survival on real OEM lock screen, physical accelerometer impact, and carrier SMS delivery (Botswana Twilio / cellular SMS).

## Exact Next Step
Implement **Phase 2 (Mobile escort & duress)** in `mokgosi-mobile/`:
1. Modularize `lib/` into `config/mokgosi_config.dart`, `services/pin_guard.dart`, `services/notification_guard.dart`, `services/motion_telemetry.dart`, `services/incident_api.dart` (with offline persistence queue, exponential backoff, connectivity listener, SMS fallback, and Route 3 consenting 15s audio upload), and `screens/{escort_home.dart, checkin_prompt.dart, decoy_safe_screen.dart, safety_setup_screen.dart}`.
2. Add Android `<service>` for foreground location/microphone monitoring in `AndroidManifest.xml`.
3. Add unit and widget tests for PIN guard (safe, duress, 3-strike duress), motion telemetry (`>= 3.5g` peak tracking), offline queue idempotency (`client_event_id`), and covert decoy screen (`pushAndRemoveUntil` + `PopScope(canPop: false)`).
