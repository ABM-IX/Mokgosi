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
   Open `http://localhost:5173`, authenticate with your responder session (or `DEMO_RESPONDER_TOKEN` when `VITE_DEMO_MODE=true`), and click **`Sound for critical alerts: off`** in the top bar to turn sound on.
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
     **`Do not call or text this person`**
     *Direct outreach is blocked by system policy because the survivor may be in earshot of an abuser.*
   - Point out the **Consents Banner**: Location granted, Audio withheld by default, Direct contact blocked.
   - Point out the **Survivor Pattern Signal**: *"Repeat Incident Signal: 2 incidents on record for this device identity."*
   - Point out that **Municipal CCTV is hidden by default** to protect domestic residential privacy.
5. **Accredited Referral Handoff:**
   - Select **`Kagisano Women's Shelter Project`** in the Referral Panel, type *"Safe accommodation requested; child with survivor"*, and click **`Record referral`**.
   - Referral is logged immutably to `incident_referrals` and added to the audit trail.
6. **Survivor Evidence Mode (Documenting Harm):**
   - Enter Safe PIN **`2580=`** to open Mokgosi $\rightarrow$ open **`Support`** $\rightarrow$ tap **`Journal`**.
   - Tap **`Write a note`**. (*Sample recording* and *Sample photo* appear in demo builds only and add placeholders: real capture is not built yet.)
   - Select 2 documented entries $\rightarrow$ tap **`Share`** $\rightarrow$ choose *Lawyer or legal aid* $\rightarrow$ **`Create link`** $\rightarrow$ generates a cryptographically signed ZIP bundle with SHA-256 manifests, an Ed25519 signature, and `verify_manifest.py`.

---

## 3. On the move: a timed walk

1. **Active Escort:**
   - In Mokgosi, open **`Getting around`** $\rightarrow$ tap **`Start a 30-second walk`**.
   - Tap **`Check in now`** to open the 15-second "Are you OK?" check.
   - Enter Safe PIN **`2580`** to confirm arrival cleanly.
2. **Impact Detection & Man-Down Fall:**
   - Open **`Demo tools`** (demo builds only), tap **`Simulate a hard impact (4.2 g)`** and let the check-in time out.
   - A `P1_CRITICAL` alert dispatches to the **Safer Communities** console.
3. **Authorized 150m CCTV Mesh:**
   - Switch the console to **`Public safety`** $\rightarrow$ the incident view shows the location, the 150 m circle and nearby opt-in cameras.
   - Click **`View camera`** $\rightarrow$ **`Save signed snapshot`** (signed with the server's Ed25519 key).
   - In **`Evidence and activity log`**, click **`Check signature`** $\rightarrow$ *Signature valid*.
   - Click **`Test with a changed copy`** $\rightarrow$ *The changed copy was rejected, as it should be.*
4. **Community Hotspots View (Spatial Insight with Privacy):**
   - Click **`Area trends`**.
   - Show the ~500 m areas. Areas with fewer than 5 incidents (10 for GBV) are left out, so no person or home can be picked out.

---

## 4. No signal

1. **Airplane / Offline Mode Rehearsal:**
   - In **`Demo tools`**, turn on **`Pretend there’s no signal`**.
   - Tap **`Send SOS`**.
   - Highlight: **no false "sent" message**. The app says the alert is queued and will send by itself, and opens the SMS app if a trusted number is set.
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
