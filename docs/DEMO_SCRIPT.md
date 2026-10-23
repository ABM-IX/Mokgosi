# MOKGOSI — 4.5-Minute Live Hackathon Demo Script

**Track:** Safer Communities & Gender-Based Violence (GBV) Response  
**Tagline:** *"Your call for help. A connected response."*

---

## Pre-Flight Setup (2 Minutes Before Pitch)

1. **Start FastAPI Backend** (`mokgosi-backend/`):
   ```powershell
   cd mokgosi-backend
   .\.venv\Scripts\uvicorn.exe main:app --env-file .env --reload
   ```
2. **Start Responder Command Center** (`mokgosi-dashboard/`):
   ```powershell
   cd mokgosi-dashboard
   npm run dev
   ```
   Open `http://localhost:5173`, authenticate with your responder session (or `DEMO_RESPONDER_TOKEN` when `VITE_DEMO_MODE=true`), and click **`🔊 Arm P1 Audio Alert`** in the top header.
3. **Launch Flutter Escort App** (`mokgosi-mobile/`):
   ```powershell
   cd mokgosi-mobile
   flutter run --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 --dart-define=MOKGOSI_DEVICE_API_KEY=<device-key> --dart-define=MOKGOSI_DEMO_MODE=true
   ```

---

## Minute 0:00 – 0:45 | The Problem & Core Engineering Invariant
- **Narrator:** *"In GBV and high-risk commute scenarios, reactive panic buttons fail when a survivor is coerced into cancelling an alarm, loses signal, or waits on cloud AI. Mokgosi is built around one non-negotiable invariant: **the safety response works even when AI, the database, or the network fails.**"*
- Show the mobile app home screen:
  - Select **`Unsafe at Home / Partner`** (`GBV_DOMESTIC` category).
  - Highlight the explicit survivor consent toggles (`Share live GPS & match authorized 150m cameras` and `Consent to 15s post-alert acoustic triage clip — 72h retention`).

---

## Minute 0:45 – 1:45 | Active Escort & Covert Duress (`0852`)
1. Tap **`START 30 SECOND ESCORT`**.
   - Point out the Android foreground service notification: *"Mokgosi Escort Active — Monitoring route & motion sensors."*
2. Tap **`CHECK IN NOW`** (or let the 30s countdown reach 0) to trigger the **15-second Haptic Check-In Window**.
3. **First, show Safe PIN (`2580`):** Enter `2580` and tap **`CONFIRM SAFE / DURESS`** — the timer resets cleanly.
4. **Next, show Coerced Duress (`0852`):** Open check-in again, enter **`0852`**, and tap **`CONFIRM SAFE / DURESS`**.
   - **On the Phone:** The screen immediately transitions to the neutral white **`Journey Completed — Location sharing turned off`** decoy screen. Press the Android Back button to prove `PopScope(canPop: false)` blocks navigation back to the escort screen, and point out there is zero mention of an alert anywhere on the phone.
   - **On the Responder Dashboard:** In $< 1\text{ second}$, a `P1_CRITICAL` card appears at the top of the queue with the audible alert and a red warning banner:
     **`⚠️ SILENT DURESS — do NOT call or message the user`**, alongside the GBV Responder Referral Protocol panel.

---

## Minute 1:45 – 2:45 | Simultaneous Dual-Routing & Acoustic Escalation Aid
1. Point out the backend terminal / audit trail showing **Simultaneous Dual-Routing**:
   - **Route 1 (Trusted Person):** Dispatched independently (`TRUSTED_CONTACT_DEMO_LOGGED` in console mode or SMS via Twilio/Webhook).
   - **Route 2 (Command Center):** Persisted in Supabase with 2 matched Gaborone CBD opt-in cameras within 150m.
2. On the mobile rehearsal drawer, tap **`Simulate Physical Impact (4.2g)`** and let the 15s check-in expire to show a `P2_HIGH` / `P3_VERIFY` incident.
3. On the dashboard **AI Acoustic & Sensor Context** card (explicitly labelled `DETERMINISTIC_DEMO — NOT YAMNET`):
   - Click **`DEMO: Conversation`** — tags attach (`Speech / Conversation (0.88)`), and the incident is **never** downgraded or hidden.
   - Click **`DEMO: Distress Profile`** — priority upgrades automatically to **`P1_CRITICAL`** with explainable tags (`Screaming (0.91)`, `Groan / Struggle (0.78)`).

---

## Minute 2:45 – 3:45 | Authorized 150m CCTV Mesh & Ed25519 Tamper-Evident Vault
1. On the **Tactical Map**, point out the pulsing incident pin, the 150m PostGIS radius circle, and the green directional **Camera FOV Cones** (`Gaborone CBD - SafeCity Pole #04` and `Main Mall Retail Opt-In Cam #02`).
2. Click **`Open Authorized Stream & Snapshot`**:
   - Show the controlled CCTV modal (which logs `OPEN_CCTV_STREAM` in the append-only audit trail).
   - Click **`Capture Signed Snapshot (Ed25519)`** to hash the frame (`SHA-256`) and sign the canonical JSON manifest with the backend's persistent `Ed25519` key.
3. Scroll to the **Cryptographic Evidence Docket**:
   - Click **`Verify Signature (Ed25519)`** $\rightarrow$ green badge: **`✓ VALID — Canonical JSON & Ed25519 Signature Verified`**.
   - Click **`Simulate 1-Byte Tamper Test`** $\rightarrow$ red badge: **`✗ INVALID — Tampered Payload Rejected by Ed25519 Verifier`**.
   - Step the incident through the enforced 4-step responder state machine: **`1. Acknowledge`** $\rightarrow$ **`2. Assign`** $\rightarrow$ **`3. Dispatch Unit`** $\rightarrow$ **`4. Resolve`**.

---

## Minute 3:45 – 4:30 | Live Fault-Tolerance Moment
1. On the phone, toggle **`Simulate Airplane / Offline Mode`** on and tap **`SEND SOS`**.
2. Show that the app **never** lies that an alert was sent — it displays **`Queued — no signal. Will send automatically when online. Device SMS fallback opened.`**
3. Toggle **`Simulate Airplane / Offline Mode`** off: the queued alert flushes automatically with its original `client_event_id`, producing exactly **one** deduplicated `P1_CRITICAL` incident on the Command Center console.

