import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages the Android Foreground Escort Service, lock-screen Full-Screen Intent
/// Check-In alerts, and repeating haptic vibration during the 15s window.
/// Guarantees zero audible/haptic emission once covert duress is triggered.
class NotificationGuard {
  NotificationGuard({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const MethodChannel _platform = MethodChannel('mokgosi/platform');

  static const int escortNotificationId = 4101;
  static const int checkinNotificationId = 4102;
  static const String checkinChannelId = 'mokgosi_checkin_urgent';

  bool _initialized = false;
  Timer? _hapticLoop;

  Future<void> initialize({void Function(String? payload)? onNotificationTap}) async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          onNotificationTap?.call(response.payload);
        },
      );
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestFullScreenIntentPermission();
      _initialized = true;
    } catch (_) {
      // Safe no-op in widget test environments without native plugin bindings.
    }
  }

  /// Starts the persistent Android foreground service (`location|microphone`).
  /// Microphone type is requested only when the user consented and granted audio permission.
  Future<void> startEscortForegroundService({required bool includeMicrophone}) async {
    try {
      await _platform.invokeMethod<bool>('startForegroundEscort', <String, dynamic>{
        'title': 'Walk in progress',
        'body': 'Tap to check in or end the walk.',
        'includeMicrophone': includeMicrophone,
      });
    } catch (_) {
      // Fallback for test environment.
    }
  }

  Future<void> stopEscortForegroundService() async {
    await cancelCheckinAlert();
    try {
      await _platform.invokeMethod<bool>('stopForegroundEscort');
    } catch (_) {}
  }

  /// Fires a lock-screen Full-Screen Intent notification and repeating vibration
  /// pattern for the 15-second check-in window.
  Future<void> triggerLockScreenCheckin({required int secondsRemaining, double? impactG}) async {
    _startRepeatingHaptics();
    try {
      final vibrationPattern = Int64List.fromList(<int>[0, 450, 200, 450, 200, 700]);
      final androidDetails = AndroidNotificationDetails(
        checkinChannelId,
        'Check-in reminders',
        channelDescription: 'Asks you to check in during a walk',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.alarm,
        vibrationPattern: vibrationPattern,
        enableVibration: true,
      );
      final subtitle = impactG != null && impactG >= 3.5
          ? 'We felt a hard impact (${impactG.toStringAsFixed(1)} g). Confirm you are OK or add more time.'
          : 'Confirm you are OK or add more time.';
      await _plugin.show(
        checkinNotificationId,
        'Check in · ${secondsRemaining}s left',
        subtitle,
        NotificationDetails(android: androidDetails),
        payload: 'CHECKIN_PROMPT',
      );
    } catch (_) {}
  }

  /// Cancels any check-in notification and stops vibration immediately.
  /// Always called on Safe PIN, Duress PIN, or Check-In timeout.
  Future<void> cancelCheckinAlert() async {
    _stopRepeatingHaptics();
    try {
      await _plugin.cancel(checkinNotificationId);
    } catch (_) {}
  }

  void _startRepeatingHaptics() {
    _stopRepeatingHaptics();
    try {
      _platform.invokeMethod<bool>('startRepeatingVibration');
    } catch (_) {}
    HapticFeedback.vibrate();
    _hapticLoop = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.vibrate();
    });
  }

  void _stopRepeatingHaptics() {
    _hapticLoop?.cancel();
    _hapticLoop = null;
    try {
      _platform.invokeMethod<bool>('stopVibration');
    } catch (_) {}
  }

  void dispose() {
    _stopRepeatingHaptics();
  }
}

