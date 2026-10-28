# MOKGOSI — Privacy, Threat Model & Survivor Safety Specification

## 1. Overview & Core Philosophy

Mokgosi is architected around two foundational pillars sharing a unified resilient engine:
- **Pillar A — Safer Communities (Public Space):** Active escort, municipal authorized CCTV mesh, and aggregated community insights.
- **Pillar B — GBV Response (Private/Home Space):** Covert help-seeking, survivor-owned evidence documentation, safe-network escalation, and accredited support routing.

In domestic violence, intimate-partner violence, and known-perpetrator environments, **a conventional panic button app can actively endanger the survivor**. If an abuser has physical device access, monitors phone activity, or intercepts notifications, any visible safety application or inbound responder communication risks triggering immediate physical harm.

---

## 2. Threat Model Matrix (Pillar B: Private & Coercive Environments)

| Threat Vector | Risk to Survivor | Mokgosi Mitigation | Residual Limitations (Honest Scope) |
| :--- | :--- | :--- | :--- |
| **Abuser Inspects Device Screen & Launcher** | Abuser discovers a GBV or safety application on the phone, leading to suspicion or assault. | **Disguised Launcher (`.CalculatorAlias`):** App icon and label display as a fully working calculator. Calculating `7 * 6 = 42` performs standard arithmetic. Entering **Safe PIN (`2580=`)** unlocks Mokgosi; entering **Duress PIN (`0852=`)** silently dispatches a covert SOS and remains on the calculator without feedback. | **Currently defeated (pre-deploy item 2, open):** the manifest declares two launcher entries, so both "Mokgosi" and "Calculator" icons appear, and the app label in Settings and permission dialogs is "Mokgosi". The package name is `com.example.mokgosi_mobile`. |
| **Recent-Apps Task Switcher Inspection** | Abuser double-taps app switcher or swipes up to view recently active app screenshots. | **`FLAG_SECURE` Native Window Protection:** `MainActivity.kt` enforces `FLAG_SECURE` on Android, rendering the app thumbnail completely blank/black in the recent-apps overview and preventing screen captures. | Does not prevent an abuser watching the physical screen over the user's shoulder while the app is active. |
| **Abuser Demands Phone Unlock (Shoulder-Surfing)** | Abuser demands the user unlock the app or reveal what they were doing. | **Quick-Exit Button & Duress PIN:** A high-visibility quick-exit control on every Pillar B screen instantly clears the navigation stack and jumps to the calculator disguise. Entering Duress PIN `0852=` silently queues `COVERT_SOS` and leaves the user on a neutral calculator. | Physical coercion where an abuser forces the survivor to operate the phone under threat cannot be solved by software alone. |
| **Inbound Responder Phone Call or SMS** | Well-meaning dispatcher or emergency service calls or texts the survivor's handset during/after an alert, exposing them. | **Strict Silent Protocol Override:** Responders are prohibited from contacting the survivor directly after a `DURESS_PIN`, `COVERT_SOS`, or `SHAKE_SOS` alert. The command dashboard displays a persistent red warning banner: **`⚠️ SILENT DURESS / COVERT ALERT — do NOT call or message the user`**. Direct outreach is blocked by default. Coordination proceeds exclusively through the Safe Network or designated partner welfare checks. | Requires dispatcher and responder adherence to standard operating procedures (SOPs). |
| **Covert Trigger Exposure (Sound / Vibration / Toast)** | Handset vibrates, beeps, or shows an on-screen toast when an emergency alert is triggered. | **Zero Sensorial Feedback:** Covert triggers (`COVERT_SOS`, `SHAKE_SOS`, `DURESS_PIN`) produce **no sound, no vibration, no toast, and no system notifications**. **Not yet true:** the foreground-service notification text is fixed ("Mokgosi Escort Active"); neutral, user-chosen wording is open (pre-deploy item 2). | If the device is set to loud haptic feedback at the OS level, native button clicks may make mechanical sound. |
| **Itemized Cellular Billing & SMS Interception** | Abuser controls the cellular contract and inspects itemized SMS billing records for outbound SMS messages to emergency numbers. | Alerts travel via encrypted HTTPS when data is active. If data is unavailable, dual-routing SMS fallback dispatches to the survivor's pre-selected trusted contacts (e.g., family or trusted friend), not to easily identifiable emergency shortcodes. | Carrier itemized billing statements will show standard SMS messages sent to those personal phone numbers. |
| **Shared Cloud Accounts (Google Photos / Drive / iCloud)** | Captured photos, audio recordings, or documents auto-sync to shared cloud family drives where the abuser can view them. | **Encrypted Local Sandbox & Private Storage:** Evidence photos and audio captured in Evidence Mode bypass the system camera roll/gallery and are saved directly into the app's encrypted local vault. Server uploads go to a private, non-public Supabase bucket with restricted RLS policies. | If the entire phone filesystem is compromised or cloned via commercial stalkerware, local files may be exposed. |
| **Malicious or Compromised Trusted Contact** | A contact in the safe network leaks information to the abuser or is coerced into sharing it. | **Sequential Escalation with Signed Token:** Alerts are dispatched in order of priority (1 to 5). Each receives an expiring, signed acknowledgement link (`/ack/{token}`). No live GPS tracking breadcrumbs are exposed to contacts who have not acknowledged. Setup guidance explicitly instructs: *"Choose someone you trust whom the person causing harm cannot access or pressure."* | A trusted contact who betrays trust remains an inescapable human risk factor. |
| **Stalkerware / Keyloggers / Rooted Devices** | Abuser has installed commercial spyware or an OS keylogger on the phone. **Not encrypted today:** on-device data (profile, PIN hashes, queued alerts, cached contacts and evidence) sits in app-private Android SharedPreferences, which a rooted or backed-up phone can read. `flutter_secure_storage`/AES is not implemented. | **Cannot mitigate:** If the operating system itself is compromised at root level, keystrokes, memory, and screen content can be intercepted by spyware. |

---

## 3. Data Minimisation, Retention, and Survivor Sovereignty

1. **Anonymous Identity by Design:**
   - Survivors are not required to provide real names, national ID (Omang) numbers, or personal phone numbers.
   - `POST /api/v1/devices/register` issues a random `user_id` (UUIDv4) and a per-device token; it collects no name, email, phone or national ID. **The mobile app does not call it yet** (pre-deploy item 3, open): it still shows a login screen that accepts any email and stores it as the user ID.
2. **Granular Consent Toggles (`user_consents`):**
   - **Location:** Granted or withheld per session.
   - **Audio Telemetry:** Disabled by default. Only enabled if explicitly toggled on by survivor.
   - **Responder Direct Contact:** Disabled by default for all covert alerts and domestic cases.
   - **Evidence Sharing:** Evidence remains strictly private in the survivor vault until the survivor chooses specific items to package into an expiring case bundle.
3. **Survivor-Controlled Deletion & Emergency Purge:**
   - **Local Emergency Purge:** Accessible from the Consents screen behind PIN confirmation. Clears all cached evidence, contacts, offline queues, and tokens from the device immediately.
   - **Server Purge (`DELETE /api/v1/me/data`, device token required):** deletes the caller's trusted contacts, evidence entries and their stored media, consents, survivor profile and device rows, then audits the counts. Append-only manifests (hashes), audit logs and incident rows (keyed by the random ID) remain. Before 2026-10-29 the old endpoint only wrote an audit row and deleted nothing. The mobile purge button is not yet wired to the new endpoint (item 3).
   - **Evidence Item Deletion (`DELETE /api/v1/evidence-entries/{id}`):** Soft-deletes and optionally hard-deletes media files from the private bucket, recording an honest audit log without media contents.
4. **Coarse Grid Hotspot Privacy (K-Anonymity):**
   - The analytics endpoint (`GET /api/v1/analytics/hotspots`) aggregates incidents into coarse ~500m grid cells.
   - **Strict K-Anonymity Suppression:** Any cell with fewer than 5 incidents (or fewer than 10 GBV incidents) is completely suppressed.
   - Individual coordinates, timestamps finer than day-level, and user identifiers are never exposed.

5. **The app key is a weak gate, by design of how APKs work:**
   - `X-Device-Key` (`DEVICE_API_KEYS`) is compiled into every APK. Anyone can extract it in minutes, so it only
     tells the API "probably our app". It never identifies a survivor and is not a secret worth protecting.
   - **Real isolation is the per-device token** (`X-Device-Token`). It is issued once at registration; the server
     stores only its SHA-256 (`devices.device_key_hash`) and derives the survivor's `user_id` from it. A `user_id`
     in a request body or query is ignored or refused (403/404) if it is not the token's own. Contacts, consents,
     evidence, case bundles and data deletion all require the token.
   - An SOS is never refused for lacking a token. Without one, the incident is stored as `unverified:<label>`, and the
     server-stored safe network is **not** messaged, so knowing someone's `user_id` cannot make the server text their contacts.
   - Rate limits are per registered device (`RATE_LIMIT_PER_MINUTE`) and per IP (`RATE_LIMIT_PER_IP_PER_MINUTE`),
     plus `REGISTRATIONS_PER_IP_PER_HOUR`. There is no bucket shared by every install. Limits are in-memory per process,
     so they reset on restart and do not span multiple instances. Several phones behind one carrier NAT share the per-IP bucket.

---

## 4. Legal & Regulatory Status (Honest Botswana Compliance Statement)

> [!CAUTION]
> **LEGAL AND REGULATORY DISCLAIMER:**
> 1. Mokgosi is a personal project in active development. It has not been released to the public.
> 2. **No Legal Review:** Mokgosi has **NOT** undergone formal legal review by accredited attorneys in Botswana.
> 3. **No Data Protection Act Certification:** Mokgosi has **NOT** been certified by or registered with the Information Commissioner under the **Botswana Data Protection Act, 2018 (Act No. 32 of 2018)**.
> 4. **Evidentiary Admissibility:** The Ed25519 digital signatures and SHA-256 manifests generated by Mokgosi provide cryptographic tamper-detection. However, their statutory admissibility under the **Cybercrime and Computer Related Crimes Act (2018)** or the **Criminal Procedure and Evidence Act (Cap 08:02)** has not been tested or certified in Botswana courts.
> 5. **Partner Unverified Status:** No partnership, memorandum of understanding (MOU), or endorsement exists with the Botswana Police Service, Department of Gender Affairs, or any NGO. All partner data is clearly flagged `verified = false`.
