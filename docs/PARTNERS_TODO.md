# MOKGOSI — Partner Verification Checklist (`PARTNERS_TODO.md`)

> [!IMPORTANT]
> **STRICT HONESTY REQUIREMENT:**
> In accordance with Mokgosi engineering invariants, **zero phone numbers, email addresses, or formal partnerships have been invented**.
> Every organization listed below is marked `UNVERIFIED` in the database (`referral_partners.verified = false`).
> Before launching in Botswana or exposing callable numbers to survivors, the team must execute formal Memorandums of Understanding (MOUs) and verify every operational detail below.

---

## 1. Statutory & Law Enforcement Partners

### Botswana Police Service (BPS) — Gender & Child Protection Branch
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false` in `database/schema.sql`)
- **Facts to Confirm Before Launch:**
  1. **Direct GBV Desk Telephone Numbers:** Obtain official, non-emergency-desk landline and mobile numbers for Gaborone Central, Broadhurst, Mogoditshane, Urban (Francistown), and Maun police stations.
  2. **Silent Welfare Check SOP:** Formally confirm whether police units can be dispatched under a silent welfare check protocol (no sirens, unmarked/un-amplified approach) to avoid endangering a survivor during covert duress.
  3. **Digital Evidence Acceptance:** Confirm police requirements for accepting cryptographically sealed case bundles (SHA-256 hash manifests, Ed25519 signatures, timestamped audio/photo dockets) under the Cybercrime and Computer Related Crimes Act (2018).
  4. **Escalation Notification:** Agreement on automated SMS / webhook notifications to the station desk for P1 critical alerts.

### Department of Gender Affairs (Ministry of Youth, Gender, Sport & Culture)
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false`)
- **Facts to Confirm Before Launch:**
  1. **Crisis Support Directory:** Obtain verified hotline and regional office intake numbers across all 10 administrative districts.
  2. **After-Hours Social Worker Protocol:** Confirm whether on-call social workers are available for crisis intervention outside standard government operating hours (07:30 – 16:30 M–F).
  3. **Shelter Placement Pathway:** Verify protocol for routing domestic violence survivors with children to emergency safe homes.

### Legal Aid Botswana
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false`)
- **Facts to Confirm Before Launch:**
  1. **Emergency Restraining Order Pathway:** Confirm procedural turnaround time for emergency protection orders under the Domestic Violence Act (2008).
  2. **Direct Case Bundle Intake:** Verify whether Legal Aid attorneys can securely receive authenticated case bundles via the Mokgosi expiring link `/api/v1/evidence-bundles/{token}`.

---

## 2. Non-Governmental & Civil Society Support Organizations

### Kagisano Women's Shelter Project
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false`)
- **Facts to Confirm Before Launch:**
  1. **Helpline Numbers:** Confirm the official 24-hour crisis toll-free helpline number and cellular backup numbers.
  2. **Safe Housing Intake Criteria:** Verify intake protocols, geographic coverage, security constraints, and admission capacity.
  3. **Psycho-Social Counselling:** Confirm referral procedure for trauma counselling and peer support.

### Botswana GBV Prevention and Support Network (BGBVN)
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false`)
- **Facts to Confirm Before Launch:**
  1. **National NGO Directory:** Confirm accredited affiliate NGOs in Maun, Kasane, Ghanzi, Selebi-Phikwe, and Lobatse.
  2. **Languages Supported:** Document languages spoken by staff (Setswana, English, Ikalanga, Shekgalagari, San dialects).

### Lifeline Botswana / Mental Health Helplines
- **Status:** `UNVERIFIED` (Placeholder seeded with `verified = false`)
- **Facts to Confirm Before Launch:**
  1. **Crisis Line Numbers:** Verify active phone numbers and hours of telephone counseling availability.
  2. **Triage Agreement:** Agreement on warm handoff protocols when an alert indicates acute psychological trauma or suicidality.

---

## 3. Telecommunications & Infrastructure Providers

### Telecom Providers (Mascom, Orange Botswana, BTC)
- **Status:** `UNVERIFIED`
- **Facts to Confirm Before Launch:**
  1. **Zero-Rated Shortcode:** Negotiate USSD/SMS zero-rating for emergency telemetry and SMS notifications so users with zero airtime/data can send alerts.
  2. **Dual-Routing SMS Gateway SLA:** Establish contractual SMS delivery latency benchmarks (< 5 seconds delivery guarantee within Botswana mobile networks).
  3. **Cell Broadcast / Mesh Coordination:** Investigate potential for localized emergency alerting via cellular mesh or emergency cell broadcast.

---

## 4. Legal & Regulatory Compliance Reviews

1. **Botswana Data Protection Act (2018):**
   - Retain accredited privacy counsel in Gaborone to complete a formal Data Protection Impact Assessment (DPIA).
   - Register Mokgosi data processing operations with the Information and Data Protection Commission.
2. **Cybercrime & Computer Related Crimes Act (2018):**
   - Obtain formal legal opinion on the chain-of-custody admissibility of Ed25519 manifests and client-signed hashes in Botswana Magistrates Courts and High Court.
3. **Survivor Consent & Parental/Guardian Framework:**
   - Formalize legal protocols for minors or individuals lacking legal capacity seeking covert help.
