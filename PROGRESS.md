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
- **Phase G1 (Data model & taxonomy):** DONE (`database/migrations/002_gbv.sql`, folded into `database/schema.sql`, extended category/trigger taxonomies, `trusted_contacts` 5-contact limit trigger & priority/role, `incident_notifications`, `evidence_entries`, `referral_partners` unverified seed without phone numbers, `incident_referrals` append-only triggers, `user_consents`, anonymous `survivor_profiles`, RLS on all 13 tables, 33/33 pytest passing)
- **Phase G2 (Backend safe network, evidence, referrals):** DONE (`/api/v1/network/contacts` CRUD with max 5 limit, priority escalation chain with signed `/ack/{token}` one-click confirmation, `/api/v1/evidence-entries` multipart storage & Ed25519 manifests, `/api/v1/evidence-entries/share` forensic case bundle ZIP with standalone `verify_manifest.py`, multi-tenant survivor data isolation, strictly verified `/api/v1/referrals`, `/api/v1/consents`, coarse 500m k-anonymized `/api/v1/analytics/hotspots`, `mokgosi-backend/Dockerfile`, `render.yaml`, 42/42 pytest passing)

- **Phase G3 (Mobile covert SOS, disguise, safe network):** DONE (Neutral onboarding `PillarSelectionScreen`, `CalculatorDisguiseScreen` safe PIN `2580=` / duress PIN `0852=` covert trigger, `FLAG_SECURE` recent-apps blanking, Android `.CalculatorAlias`, 3-shake trigger with cooldown, `SafeNetworkScreen` 5-contact limit & warning banner, `GetHelpScreen` verified-only directory with honest unverified notice, `ConsentsScreen` with PIN-confirmed emergency purge, Setswana + English l10n with `NEEDS_NATIVE_REVIEW` doc, 15/15 Flutter tests passing, 0 analyzer issues)
- **Phase G4 (Mobile: Evidence Mode - survivor-owned documentation):** DONE (`EvidenceScreen` with silent capture buttons for audio, photo, note; encrypted local vault; sync state indicator 'Saved on this phone' vs 'Backed up & signed'; multi-select case bundle creation with recipient selection & 2h expiring link modal; entry deletion with local & server purge; stealth screen dimming; quick exit; 21/21 Flutter tests passing, 0 analyzer issues)

## What Is Verified
- **Backend (`mokgosi-backend/`):** `.\.venv\Scripts\python.exe -m py_compile` (0 errors) and `.\.venv\Scripts\python.exe -m pytest -v` (42/42 passed across base invariants, G1 schema/RLS, and G2 safe network/evidence/referrals/hotspots).
- **Mobile (`mokgosi-mobile/`):** `flutter analyze` (0 issues), `flutter test` (21/21 passed across original escort flow, calculator disguise math/safe PIN/duress PIN, safe network contact limit, consents PIN purge, 3-shake simulation with cooldown, offline queuing & deduplication on reconnect, AndroidManifest alias validation, and evidence mode silent capture, local vault, case bundle generation, entry deletion, and quick exit).
- **Dashboard (`mokgosi-dashboard/`):** `npm test` (3/3 passed) and `npm run build` (clean production bundle).

## What Is Unverified
- Physical Android phone hardware sensors (haptic motor, native accelerometer hardware events, physical screen lock wake over OEM keyguard), and live carrier SMS delivery to Botswana (`+267`) mobile numbers.
- Live YAMNet TFLite model weights (`DEMO_MODE` deterministic profiles are used and explicitly labelled `DETERMINISTIC_DEMO`).
- Live RTSP/MJPEG municipal camera streams (seeded Gaborone CBD cameras are opt-in demo entries).
- Live local PostgreSQL container (Docker daemon requires Windows elevated GUI privilege; schema validated via SQL AST and unit test suite).
- Setswana strings marked `NEEDS_NATIVE_REVIEW` in `docs/SETSWANA_L10N.md` pending review by native Setswana speakers.

## Exact Next Step
Proceed to Phase G5: Dashboard: two pillars, one console (`mokgosi-dashboard/`):
- Pillar switch/tabs: Safer Communities (public-safety incidents: map, CCTV cones, camera modal, snapshot signing, hotspot view) and GBV Response (GBV categories).
- GBV case view: category & consent flags up front; protocol card ("Silent alert: do not call or message survivor; go through safe network"); safe network escalation status (who notified, who acked, timeline); referral panel (verified partners, "Refer to…" action); repeat-incident count & pattern timeline; read-only shared evidence docket; CCTV panel hidden by default for GBV_DOMESTIC.
- Hotspot view under Safer Communities using `GET /api/v1/analytics/hotspots` (suppresses counts < 5).


