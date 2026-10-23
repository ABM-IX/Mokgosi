# MOKGOSI Build Progress

## Phase Status Summary
- **Phase 0 (It builds):** DONE
- **Phase 1 (Backend invariant & security):** DONE (24/24 pytest tests passing)
- **Phase 2 (Mobile escort & duress):** DONE (6/6 Flutter unit & widget tests passing, 0 analyzer issues, `app-debug.apk` builds cleanly)
- **Phase 3 (Dashboard Realtime & SLA):** DONE (Priority queue, SLA timers/metrics, 4-step lifecycle state machine, authenticated responder session, SILENT DURESS banner)
- **Phase 4 (Acoustic AI context):** DONE (`DETERMINISTIC_DEMO` gated behind `DEMO_MODE`, upgrade-only priority, consenting 15s mobile upload, signed `AUDIO_CONTEXT_CLIP` manifest)
- **Phase 5 (Evidence & controlled CCTV):** DONE (`POST /api/v1/incidents/{id}/cctv-snapshot` enforcing 150m authorized camera check, `CctvStreamModal`, `EvidenceDocketModal` with live Ed25519 signature verification & 1-byte tamper test, audit logging for `VIEW_INCIDENT`, `OPEN_CCTV_STREAM`, `VIEW_EVIDENCE`)
- **Phase 6 (Fault-tolerance rehearsal):** DONE (Automated fault-tolerance tests across backend, mobile, and dashboard + [`docs/REHEARSAL.md`](docs/REHEARSAL.md))
- **Phase 7 (GBV alignment & pitch readiness):** DONE (`category` selection & display, covert defaults, survivor consent & data deletion path, non-invented `TODO` referral resources, [`docs/PRIVACY_AND_SAFETY.md`](docs/PRIVACY_AND_SAFETY.md), [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md), [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), and updated [`README.md`](docs/README.md))

## What Is Verified
- **Backend (`mokgosi-backend/`):** `.\.venv\Scripts\python.exe -m py_compile` (0 errors) and `.\.venv\Scripts\python.exe -m pytest -v` (24/24 passed).
- **Mobile (`mokgosi-mobile/`):** `flutter analyze` (0 issues), `flutter test` (6/6 passed), `flutter build apk --debug` (`build\app\outputs\flutter-apk\app-debug.apk` built).
- **Dashboard (`mokgosi-dashboard/`):** `npm test` (3/3 passed) and `npm run build` (clean production bundle).

## What Is Unverified
- Physical Android phone lock-screen wake over OEM keyguard (`showWhenLocked` / `turnScreenOn`), physical drop accelerometer calibration, and live carrier SMS delivery to Botswana (`+267`) mobile numbers.
- Live YAMNet TFLite model weights (`DEMO_MODE` deterministic profiles are used and explicitly labelled `DETERMINISTIC_DEMO`).
- Live RTSP/MJPEG municipal camera streams (seeded Gaborone CBD cameras are opt-in demo entries).

## Exact Next Step
All phases (0–7) are complete and verified. Ready for live hackathon rehearsal using [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md) and [`docs/REHEARSAL.md`](docs/REHEARSAL.md).

