/**
 * MOKGOSI GBV & SILENT ALERT RESPONDER PROTOCOLS
 * 
 * CRITICAL SAFETY REQUIREMENT:
 * Protocol text and partner contact procedures must be confirmed with accredited
 * organisations before production deployment.
 * 
 * TODO: confirm with partner organisations:
 * - Botswana Police Service (Gender & Child Protection Branch)
 * - Department of Gender Affairs (Ministry of Youth, Gender, Sport & Culture)
 * - Kagisano Women's Shelter Project
 * - Botswana GBV Prevention and Support Network (BGBVN)
 * - Legal Aid Botswana
 */

export const GBV_SAFETY_PROTOCOLS = {
  COVERT_DURESS: {
    title: 'SILENT DURESS / COVERT ALERT PROTOCOL',
    severity: 'CRITICAL_SAFETY_OVERRIDE',
    rules: [
      'DO NOT initiate direct telephone calls or SMS messages to the survivor device.',
      'The survivor may be within physical proximity or immediate earshot of a person causing harm.',
      'The survivor handset displays a covert disguise surface (e.g. standard calculator or trip decoy). Inbound alerts destroy covert cover.',
      'Coordinate exclusively through the survivor designated Safe Network (trusted contacts) or dispatch a silent welfare check according to local standard operating procedures.',
      'Treat location as an approximation; respect private residential boundaries.',
    ],
    confirmationStatus: 'TODO: confirm with partner organisations',
  },
  DOMESTIC_RESIDENCE: {
    title: 'PRIVATE DOMESTIC RESIDENCE PROTOCOL',
    severity: 'PRIVACY_PROTECTION',
    rules: [
      'Public CCTV cameras and cones are automatically suppressed for domestic/residential incidents.',
      'Do not display public camera streams unless the incident occurs in a public right-of-way.',
      'Preserve survivor-controlled evidence access; only survivor-shared dockets are viewable.',
    ],
    confirmationStatus: 'TODO: confirm with partner organisations',
  },
  ESCALATION_CHAIN: {
    title: 'SAFE NETWORK PRIORITY ESCALATION',
    description:
      'Contacts are notified in order of priority (1 to 5). Each receives a signed, expiring acknowledgement link (/ack/{token}). If contact N fails to acknowledge within the escalation window, notification escalates to contact N+1.',
    confirmationStatus: 'TODO: confirm with partner organisations',
  },
};

export const VERIFIED_REFERRAL_PARTNERS = [
  {
    id: 'bps-gbv-desk',
    name: 'Botswana Police Service — Gender & Child Protection Desk',
    type: 'POLICE',
    region: 'National',
    phone: 'TODO: verify official desk number',
    hours: '24/7',
    verified: false,
    verified_source: 'National Police Service Registry (pending formal MOU)',
    notes: 'Silent welfare check protocol must be requested for covert alerts.',
  },
  {
    id: 'dept-gender-affairs',
    name: 'Department of Gender Affairs — Crisis Coordination',
    type: 'GBV_DESK',
    region: 'Gaborone / Central',
    phone: 'TODO: verify official hotline',
    hours: '07:30 - 16:30 M-F',
    verified: false,
    verified_source: 'Government Directory (pending operational agreement)',
    notes: 'Coordinates social work intake, temporary shelter placement, and counselling.',
  },
  {
    id: 'kagisano-shelter',
    name: 'Kagisano Women’s Shelter Project',
    type: 'SHELTER',
    region: 'South / Gaborone',
    phone: 'TODO: verify official helpline',
    hours: '24/7 Crisis Helpline',
    verified: false,
    verified_source: 'NGO Coordination Registry (pending MOU)',
    notes: 'Emergency safe housing, psycho-social support, and crisis counselling.',
  },
  {
    id: 'legal-aid-bw',
    name: 'Legal Aid Botswana — GBV Support Services',
    type: 'LEGAL',
    region: 'National',
    phone: 'TODO: verify official intake line',
    hours: '08:00 - 17:00 M-F',
    verified: false,
    verified_source: 'Statutory Body Registry (pending verification)',
    notes: 'Assistance with restraining orders, protective custody, and court filings.',
  },
];
