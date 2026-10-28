# MOKGOSI — Demo Walkthrough

A guided tour for showing Mokgosi to testers and prospective partner organisations. Run it in demo mode only.

**Tagline:** *"Your call for help. A connected response."*

---

## Setup

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
3. **Launch Flutter Mobile App** (`mokgosi-mobile/`):
   ```powershell
   cd mokgosi-mobile
   flutter run --dart-define=MOKGOSI_API_URL=http://10.0.2.2:8000 --dart-define=MOKGOSI_DEVICE_API_KEY=<device-key> --dart-define=MOKGOSI_DEMO_MODE=true
   ```

---

## 1. What Mokgosi covers

- **Public safety:** timed walks with check-ins, nearby opt-in cameras, and area trends.
- **GBV response:** silent alerts, a private journal of evidence, a trusted-contact chain, and referrals to support organisations.
- The alert path keeps working when the audio analysis, the database or the network fails.

---

## 2. At home: a silent alert

1. **The Disguised Surface:**
   - Present the mobile screen: the app launcher icon and title read **`Calculator`**.
   - Type `7 * 6 =` $\rightarrow$ result displays **`42`**.
   - Show that swiping into Android Recent Apps displays a completely blank/black preview (**`FLAG_SECURE`** native window protection in `MainActivity.kt`).
2. **Covert Help-Seeking (Duress PIN `0852=`):**
   - Enter **`0852=`** on the calculator.
   - **On the Phone:** Zero sound. Zero vibration. Zero toast. The screen stays calmly on the calculator with zero visual clue that an alert was sent.
   - Point out the foreground service notification reads **"Calculator Running"**, never "Mokgosi" or "Emergency".
3. **Safe-Network Priority Escalation & One-Click Acknowledgement:**
   - Show the backend console: `COVERT_SOS` dispatches to Contact #1 (Sister/Mother) with an expiring, signed `/ack/{token}` link.
   - Open `/ack/{token}` in a browser $\rightarrow$ click the single **"I've got this"** button. Notification status immutably marks `ACKNOWLEDGED`. (If not acked within escalation seconds, it automatically cascades to Contact #2).
4. **Command Console GBV Case View:**
   - The dashboard alerts in $< 1\text{ second}$ and automatically activates the **GBV Response** pillar tab.
   - Point out the prominent **Protocol Card**:
     **`⚠️ SILENT ALERT PROTOCOL: DO NOT CALL OR MESSAGE THE SURVIVOR.`**
     *Direct outreach is blocked by system policy because the survivor may be in earshot of an abuser.*
   - Point out the **Consents Banner**: Location granted, Audio withheld by default, Direct contact blocked.
   - Point out the **Survivor Pattern Signal**: *"Repeat Incident Signal: 2 incidents on record for this device identity."*
   - Point out that **Municipal CCTV is hidden by default** to protect domestic residential privacy.
5. **Accredited Referral Handoff:**
   - Select **`Kagisano Women's Shelter Project`** in the Referral Panel, type *"Safe accommodation requested; child with survivor"*, and click **`Record Formal Referral & Log Audit`**.
   - Referral is logged immutably to `incident_referrals` and added to the audit trail.
6. **Survivor Evidence Mode (Documenting Harm):**
   - Enter Safe PIN **`2580=`** to open Mokgosi $\rightarrow$ tap **`Evidence Vault`**.
   - Show silent capture buttons (*Record Audio*, *Take Photo*, *Write Note*).
   - Select 2 documented entries $\rightarrow$ tap **`Create Case Bundle`** $\rightarrow$ select *Legal Aid* $\rightarrow$ generates a cryptographically signed ZIP bundle with SHA-256 manifests, an Ed25519 signature, and `verify_manifest.py`.

---

## 3. On the move: a timed walk

1. **Active Escort:**
   - In Mokgosi, tap **`Getting Around Safely`** $\rightarrow$ tap **`Start 30 Second Escort`**.
   - Tap **`Check In Now`** to trigger the 15-second haptic check-in window.
   - Enter Safe PIN **`2580`** to confirm arrival cleanly.
2. **Impact Detection & Man-Down Fall:**
   - In the mobile rehearsal drawer, trigger **`Simulate Physical Impact (4.2g)`** and let the check-in timeout.
   - A `P1_CRITICAL` alert dispatches to the **Safer Communities** console.
3. **Authorized 150m CCTV Mesh:**
   - Switch console to **`Safer Communities`** $\rightarrow$ Tactical Map displays the pulsing incident pin and authorized camera cones (`Gaborone CBD SafeCity Pole #04`).
   - Click **`Open Authorized Stream & Snapshot`** $\rightarrow$ captures frame and signs with persistent Ed25519 private key.
   - In the Evidence Docket, click **`Verify Signature (Ed25519)`** $\rightarrow$ **`✓ VALID`**.
   - Click **`Simulate 1-Byte Tamper Test`** $\rightarrow$ **`✗ INVALID`** (cryptographic rejection).
4. **Community Hotspots View (Spatial Insight with Privacy):**
   - Click **`Community Hotspots & Density (Aggregated)`**.
   - Show the coarse ~500m grid table. Point out the **K-Anonymity Privacy Guarantee**: cells under 5 incidents are strictly suppressed. No personal coordinates or survivor identities are ever exposed.

---

## 4. No signal

1. **Airplane / Offline Mode Rehearsal:**
   - In the mobile rehearsal drawer, toggle **`Simulate Airplane / Offline Mode`** ON.
   - Tap **`Send SOS`**.
   - Highlight: **No false "sent" message**. The app states: *"Queued — no signal. Retrying automatically; SMS fallback triggered."*
   - Toggle offline mode OFF: the queued alert immediately flushes and arrives at the command center with zero duplication.
2. **Independent Routing Invariant:**
   - Emphasize: Even if the database crashes or AI is offline, the Trusted Network SMS fallback and the Command Center alerts fire independently. Neither path gates or cancels the other.

---

## 5. What is not real yet

Say this plainly when you demo:
- No partner organisation has confirmed its details. Referral entries stay `verified = false` until there is a signed agreement, and no phone numbers are invented.
- Mokgosi has not been reviewed under the Botswana Data Protection Act.
- The Setswana strings still need review by a native speaker (`NEEDS_NATIVE_REVIEW`).
- Audio "analysis" in demo mode is a fixed sample profile, not a model.
