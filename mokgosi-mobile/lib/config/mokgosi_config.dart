class MokgosiConfig {
  static const apiBase = String.fromEnvironment('MOKGOSI_API_URL', defaultValue: 'http://10.0.2.2:8000');
  static const deviceApiKey = String.fromEnvironment('MOKGOSI_DEVICE_API_KEY');
  static const trustedContactPhone = String.fromEnvironment('MOKGOSI_TRUSTED_CONTACT_PHONE');
  static const demoMode = bool.fromEnvironment('MOKGOSI_DEMO_MODE', defaultValue: false);
  static const demoEscortSeconds = 30;
  static const checkinSeconds = 15;
  static const safePin = '2580';
  static const duressPin = '0852';
}
