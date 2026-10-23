/// Setswana (tn) + English (en) localization dictionary.
/// Marked NEEDS_NATIVE_REVIEW in docs/SETSWANA_L10N.md.
class MokgosiL10n {
  static String currentLocale = 'en'; // 'en' | 'tn'

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'app_title': 'Mokgosi',
      'getting_around': 'Getting Around Safely',
      'getting_around_desc': 'Active escort, route tracking, and municipal mesh',
      'support_and_safety': 'Support & Safety',
      'support_and_safety_desc': 'Covert help-seeking, safe network, and survivor-owned evidence',
      'onboarding_question': 'How do you want to use Mokgosi?',
      'onboarding_subtitle': 'You can use either or both pillars. Everything can be adjusted anytime in settings.',
      'pillar_a_title': 'Getting Around Safely',
      'pillar_b_title': 'Support & Safety',
      'quick_exit': 'Quick Exit',
      'quick_exit_desc': 'Instantly hides app behind a normal calculator',
      'safe_network': 'Safe Network',
      'safe_network_desc': 'Manage up to 5 trusted contacts for priority escalation',
      'safe_network_warning':
          'Choose someone you trust who the person causing harm cannot access or pressure.',
      'priority_1': '#1 (Notified First)',
      'priority_escalation': 'Escalation Contact',
      'send_test_message': 'Send Test Message',
      'test_message_confirm':
          'Send a test message to verify this contact? They will receive a signed link to confirm.',
      'get_help': 'Get Help & Services',
      'verified_directory': 'Support Directory',
      'directory_verifying':
          'Support directory being verified with partner organisations. Formal contact details will appear once verified.',
      'referrals_verifying_notice': 'Support directory being verified',
      'referrals_verifying_body':
          'We only list support partners after formal confirmation to ensure numbers and locations are safe and operational.',
      'consents': 'Privacy & Consents',
      'consents_title': 'Privacy & Consents',
      'location_consent': 'Share Live Location During Alert',
      'audio_consent': '15-Second Acoustic Context Clip',
      'responder_contact_consent': 'Allow Responders to Contact This Phone',
      'responder_contact_warn':
          'Note: Covert and Duress alerts ALWAYS override this to DO NOT CONTACT for your safety.',
      'evidence_vault': 'Evidence Vault',
      'evidence_vault_desc': 'Private encrypted documentation owned by you',
      'remove_data': 'Remove All Mokgosi Data',
      'remove_data_desc':
          'Wipes local profile, contacts, and requests server profile deletion.',
      'remove_data_confirm':
          'Are you sure? This phone will return to an unconfigured state. Sealed forensic manifests on the server remain intact.',
      'calculator_title': 'Calculator',
      'covert_triggers': 'Covert Triggers',
      'covert_sos': 'Covert Silent SOS',
      'shake_sos_title': 'Triple-Shake Alert',
      'shake_sos_desc': 'Shake phone hard 3 times within 2 seconds to trigger silent SOS',
      'notification_disguise': 'Disguise Notification Text',
    },
    'tn': {
      'app_title': 'Mokgosi',
      'getting_around': 'Go Tsamaya ka Pabalesego',
      'getting_around_desc': 'Patelelo ya tsela, tsamaiso le khamera tsa toropo',
      'support_and_safety': 'Thuso le Tshireletso',
      'support_and_safety_desc': 'Kopo ya thuso ya sephiri, batho ba ba tshepegang le bosupi jo bo sireletsegileng',
      'onboarding_question': 'O eletsa go dirisa Mokgosi jang?',
      'onboarding_subtitle': 'O ka dirisa karolo e nngwe kgotsa ka bobedi. O ka di fetola nako nngwe le nngwe.',
      'pillar_a_title': 'Go Tsamaya ka Pabalesego',
      'pillar_b_title': 'Thuso le Tshireletso',
      'quick_exit': 'Tswa ka Potlako',
      'quick_exit_desc': 'Fitlha tiro ka sebaledi sa metlhala',
      'safe_network': 'Batho ba ke ba Tshephang',
      'safe_network_desc': 'Kgetha batho ba ba ka go thusang go fitlha go ba le batlhano',
      'safe_network_warning':
          'Tlhopha motho yo o mo tshephang yo modiragatsi wa kgokgontsho a ka sekang a mo tshosa kgotsa a bona mogala wa gagwe.',
      'priority_1': '#1 (O tlile go itsisiwe pele)',
      'priority_escalation': 'Mothusi wa bobedi',
      'send_test_message': 'Romela Molaetsa wa Tekolo',
      'test_message_confirm': 'A o eletsa go lekeletsa molaetsa go motho yo?',
      'get_help': 'Bona Thuso le Ditirelo',
      'verified_directory': 'Ditirelo tsa Thuso',
      'directory_verifying':
          'Ditirelo tsa thuso di santse di tlhotlhomisiwa semmuso. Dinomoro di tla bewa fa go fetswa tumalano.',
      'referrals_verifying_notice': 'Ditirelo tsa thuso di santse di tlhotlhomisiwa',
      'referrals_verifying_body':
          'Re beya dinomoro fela tsa ba re dumalaneng nabo semmuso gore di sireletsege e bile di dire.',
      'consents': 'Ditumelano tsa Tshireletso',
      'consents_title': 'Ditumelano tsa Tshireletso',
      'location_consent': 'Kabela Felo ga Gago ka Pabalesego',
      'audio_consent': 'Sekere sa Modumo sa Metsotswana e 15',
      'responder_contact_consent': 'Letlelela Ba-arabi go Lela Mogala Ono',
      'responder_contact_warn':
          'Ela tlhoko: Ditshwetso tsa sephiri di tima go letsediwa mogala ka botlalo go go sireletsa.',
      'evidence_vault': 'Polokelo ya Bosupi',
      'evidence_vault_desc': 'Tshedimosetso ya gago e e sireletsegileng',
      'remove_data': 'Phimola Tshedimosetso Yotlhe',
      'remove_data_desc': 'Phimola dipehelo tsotlhe mo mogaleng ono.',
      'remove_data_confirm': 'A o tlhomamisitse gore o batla go phimola tshedimosetso yotlhe?',
      'calculator_title': 'Sebaledi',
      'covert_triggers': 'Dilo tsa Sephiri',
      'covert_sos': 'Mokgosi wa Sephiri o o Didimetseng',
      'shake_sos_title': 'Tshikinyo ya Gabedi le Bonngwe',
      'shake_sos_desc': 'Tshikinya mogala ga tharo ka potlako go romela mokgosi o o didimetseng',
      'notification_disguise': 'Fetola Lebitso la Kitsiso',
    },
  };

  static String get(String key) {
    return _strings[currentLocale]?[key] ?? _strings['en']?[key] ?? key;
  }
}
