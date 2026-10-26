import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

enum PinOutcome {
  safe,
  duress,
  invalid,
  duressThreeStrikes,
}

/// Evaluates Safe vs Duress PINs using salted SHA-256 hashes and enforces
/// covert 3-strike duress escalation without cancelling active check-ins.
class PinGuard {
  PinGuard({
    String safePin = MokgosiConfig.safePin,
    String duressPin = MokgosiConfig.duressPin,
    this.salt = 'mokgosi-local-pin-salt-v2',
  })  : _safeHash = hashPin(safePin, salt),
        _duressHash = hashPin(duressPin, salt);

  PinGuard.fromHashes({
    required String safeHash,
    required String duressHash,
    required this.salt,
  })  : _safeHash = safeHash,
        _duressHash = duressHash;

  final String salt;
  String _safeHash;
  String _duressHash;
  int _consecutiveWrongAttempts = 0;

  int get consecutiveWrongAttempts => _consecutiveWrongAttempts;
  String get safeHash => _safeHash;
  String get duressHash => _duressHash;

  static final RegExp _pinFormat = RegExp(r'^\d{4}$');

  static String hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:${pin.trim()}');
    return sha256.convert(bytes).toString();
  }

  static bool isValidPinFormat(String pin) => _pinFormat.hasMatch(pin.trim());

  static String? validatePinPair(String safePin, String duressPin) {
    final s = safePin.trim();
    final d = duressPin.trim();
    if (!isValidPinFormat(s) || !isValidPinFormat(d)) {
      return 'Both Safe PIN and Duress PIN must be 4 digits.';
    }
    if (s == d) {
      return 'Safe PIN and Duress PIN must be different.';
    }
    return null;
  }

  void updatePins({required String safePin, required String duressPin}) {
    final error = validatePinPair(safePin, duressPin);
    if (error != null) {
      throw ArgumentError(error);
    }
    _safeHash = hashPin(safePin, salt);
    _duressHash = hashPin(duressPin, salt);
    _consecutiveWrongAttempts = 0;
  }

  void resetAttempts() {
    _consecutiveWrongAttempts = 0;
  }

  PinOutcome evaluate(String rawPin) {
    final candidateHash = hashPin(rawPin, salt);
    if (candidateHash == _safeHash) {
      _consecutiveWrongAttempts = 0;
      return PinOutcome.safe;
    }
    if (candidateHash == _duressHash) {
      _consecutiveWrongAttempts = 0;
      return PinOutcome.duress;
    }
    _consecutiveWrongAttempts += 1;
    if (_consecutiveWrongAttempts >= 3) {
      _consecutiveWrongAttempts = 0;
      return PinOutcome.duressThreeStrikes;
    }
    return PinOutcome.invalid;
  }
}

class MokgosiConfig {
  static const apiBase = String.fromEnvironment(
    'MOKGOSI_API_URL',
    defaultValue: 'https://mokgosi-backend.onrender.com',
  );
  static const deviceApiKey = String.fromEnvironment(
    'MOKGOSI_DEVICE_API_KEY',
    defaultValue: 'DEMO_DEVICE_KEY',
  );
  static const trustedContactPhone = String.fromEnvironment(
    'MOKGOSI_TRUSTED_CONTACT_PHONE',
  );
  static const demoMode = bool.fromEnvironment(
    'MOKGOSI_DEMO_MODE',
    defaultValue: false,
  );
  static const demoEscortSeconds = 30;
  static const checkinSeconds = 15;
  static const safePin = '2580';
  static const duressPin = '0852';
  static const gaboroneDemoLat = -24.6560;
  static const gaboroneDemoLng = 25.9090;
  static const impactThresholdG = 3.5;

  static final RegExp e164Pattern = RegExp(r'^\+[1-9][0-9]{7,14}$');

  static bool isValidE164(String phone) => e164Pattern.hasMatch(phone.trim());
}

class SafetyProfile {
  SafetyProfile({
    this.userId = 'MOKGOSI_DEMO_USER',
    this.trustedContactName = '',
    String? trustedContactPhone,
    this.escortDurationSeconds = MokgosiConfig.demoEscortSeconds,
    this.category = 'PERSONAL_SAFETY',
    this.consentLocation = true,
    this.consentAudio = false,
    this.pinToGaboroneDemoCbd = true,
  }) : trustedContactPhone =
            trustedContactPhone ?? MokgosiConfig.trustedContactPhone;

  String userId;
  String trustedContactName;
  String trustedContactPhone;
  int escortDurationSeconds;
  String category; // 'PERSONAL_SAFETY' | 'GBV_DOMESTIC'
  bool consentLocation;
  bool consentAudio;
  bool pinToGaboroneDemoCbd;

  Map<String, dynamic> toJson({
    required String safeHash,
    required String duressHash,
    required String salt,
  }) =>
      {
        'user_id': userId,
        'trusted_contact_name': trustedContactName,
        'trusted_contact_phone': trustedContactPhone,
        'escort_duration_seconds': escortDurationSeconds,
        'category': category,
        'consent_location': consentLocation,
        'consent_audio': consentAudio,
        'pin_to_gaborone_demo_cbd': pinToGaboroneDemoCbd,
        'safe_hash': safeHash,
        'duress_hash': duressHash,
        'pin_salt': salt,
      };
}

class PlatformStore {
  static const MethodChannel _channel = MethodChannel('mokgosi/platform');
  static final Map<String, String> _memoryFallback = <String, String>{};

  static Future<String?> read(String key) async {
    try {
      final value = await _channel.invokeMethod<String>('readStore', {'key': key});
      if (value != null) {
        _memoryFallback[key] = value;
        return value;
      }
    } catch (_) {
      // Fallback to in-memory store when running in unit/widget tests.
    }
    return _memoryFallback[key];
  }

  static Future<void> write(String key, String? value) async {
    if (value == null) {
      _memoryFallback.remove(key);
    } else {
      _memoryFallback[key] = value;
    }
    try {
      await _channel.invokeMethod<bool>('writeStore', {'key': key, 'value': value});
    } catch (_) {
      // Ignored in test environment.
    }
  }

  static Future<void> clear() async {
    _memoryFallback.clear();
    try {
      await _channel.invokeMethod<bool>('clearStore');
    } catch (_) {
      // Ignored in test environment.
    }
  }
}
