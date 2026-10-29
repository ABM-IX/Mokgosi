/**
 * Response guidance shown to responders, and the referral organisations they can choose from.
 *
 * None of this has been agreed with the organisations yet. Until it is, every protocol is marked
 * as draft and every partner stays `verified: false` with no contact number. Organisations to
 * confirm with: Botswana Police Service (Gender & Child Protection Branch), Department of Gender
 * Affairs, Kagisano Women's Shelter Project, Botswana GBV Prevention and Support Network, Legal Aid
 * Botswana. See docs/PARTNERS_TODO.md.
 */

const DRAFT = 'Draft guidance. Not yet agreed with partner organisations.';

export const GBV_SAFETY_PROTOCOLS = {
  COVERT_DURESS: {
    title: 'Silent alerts',
    rules: [
      'Do not phone, text or message the person’s phone.',
      'Assume the person causing harm is nearby and may be watching the phone.',
      'Work through the person’s trusted contacts, or send a discreet welfare check under your local procedure.',
      'Treat the location as approximate, and take care near private homes.',
    ],
    confirmationStatus: DRAFT,
  },
  DOMESTIC_RESIDENCE: {
    title: 'Incidents at a home',
    rules: [
      'Public cameras near a home stay hidden unless the incident is on a public street.',
      'Only look at evidence the person has chosen to share.',
    ],
    confirmationStatus: DRAFT,
  },
  ESCALATION_CHAIN: {
    title: 'Trusted contacts',
    description:
      'Contacts are messaged in the order the person chose. Each message has a link the contact uses to say they are responding. If nobody responds in time, the next contact is messaged.',
    confirmationStatus: DRAFT,
  },
};

export const VERIFIED_REFERRAL_PARTNERS = [
  {
    id: 'bps-gbv-desk',
    name: 'Botswana Police Service, Gender & Child Protection',
    type: 'POLICE',
    region: 'National',
    phone: null,
    verified: false,
    notes: 'Ask for a discreet welfare check when the alert was silent.',
  },
  {
    id: 'dept-gender-affairs',
    name: 'Department of Gender Affairs',
    type: 'GBV_DESK',
    region: 'Gaborone',
    phone: null,
    verified: false,
    notes: 'Social work intake, temporary shelter and counselling.',
  },
  {
    id: 'kagisano-shelter',
    name: 'Kagisano Women’s Shelter Project',
    type: 'SHELTER',
    region: 'Gaborone',
    phone: null,
    verified: false,
    notes: 'Safe accommodation and crisis counselling.',
  },
  {
    id: 'legal-aid-bw',
    name: 'Legal Aid Botswana',
    type: 'LEGAL',
    region: 'National',
    phone: null,
    verified: false,
    notes: 'Protection orders and court filings.',
  },
];
