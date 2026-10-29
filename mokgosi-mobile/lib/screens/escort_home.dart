import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../services/motion_telemetry.dart';
import '../services/notification_guard.dart';
import 'checkin_prompt.dart';
import 'decoy_safe_screen.dart';
import 'safety_setup_screen.dart';
import '../widgets/common.dart';

class EscortHome extends StatefulWidget {
  const EscortHome({
    super.key,
    this.initialDemoControlsOpen = MokgosiConfig.demoMode,
  });

  final bool initialDemoControlsOpen;

  @override
  State<EscortHome> createState() => _EscortHomeState();
}

class _EscortHomeState extends State<EscortHome> {
  static const String _profileStorageKey = 'mokgosi_safety_profile_v1';

  final SafetyProfile _profile = SafetyProfile();
  final PinGuard _pinGuard = PinGuard();
  final NotificationGuard _notifications = NotificationGuard();
  final MotionTelemetry _telemetry = MotionTelemetry();
  final TextEditingController _pinController = TextEditingController();

  Timer? _timer;
  int _seconds = 0;
  int _activeEscortTotalSeconds = MokgosiConfig.demoEscortSeconds;
  bool _active = false;
  bool _checking = false;
  bool _sending = false;
  bool _showDemoDrawer = false;
  int _queuedCount = 0;
  String? _activeIncidentId;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _showDemoDrawer = widget.initialDemoControlsOpen;
    _notifications.initialize();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    final queued = await IncidentApi.getQueuedEvents();
    final savedProfileJson = await PlatformStore.read(_profileStorageKey);
    if (savedProfileJson != null && savedProfileJson.isNotEmpty) {
      try {
        final map = jsonDecode(savedProfileJson) as Map<String, dynamic>;
        _profile.trustedContactName = (map['trusted_contact_name'] ?? '').toString();
        _profile.trustedContactPhone =
            (map['trusted_contact_phone'] ?? MokgosiConfig.trustedContactPhone).toString();
        _profile.escortDurationSeconds =
            (map['escort_duration_seconds'] as int?) ?? MokgosiConfig.demoEscortSeconds;
        _profile.category = (map['category'] ?? 'PERSONAL_SAFETY').toString();
        _profile.consentLocation = map['consent_location'] != false;
        _profile.consentAudio = map['consent_audio'] == true;
        _profile.pinToGaboroneDemoCbd =
            MokgosiConfig.demoMode && map['pin_to_gaborone_demo_cbd'] != false;
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _queuedCount = queued.length);
    }
  }

  Future<void> _persistProfile() async {
    await PlatformStore.write(
      _profileStorageKey,
      jsonEncode(
        _profile.toJson(
          safeHash: _pinGuard.safeHash,
          duressHash: _pinGuard.duressHash,
          salt: _pinGuard.salt,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _notifications.dispose();
    _telemetry.stopMonitoring();
    super.dispose();
  }

  void _startEscort({int? customSeconds}) {
    _timer?.cancel();
    _pinGuard.resetAttempts();
    _telemetry.resetPeakG();
    final duration = customSeconds ?? _profile.escortDurationSeconds;
    setState(() {
      _active = true;
      _checking = false;
      _activeEscortTotalSeconds = duration;
    });
    _notifications.cancelCheckinAlert();
    _notifications.startEscortForegroundService(
      includeMicrophone: _profile.consentAudio,
    );
    _telemetry.startMonitoring(
      onImpactThreshold: (_) {
        if (_active && !_checking) {
          _showCheckin(fromImpact: true);
        }
      },
    );
    _count(duration, _showCheckin);
  }

  void _count(int seconds, VoidCallback done) {
    _timer?.cancel();
    setState(() => _seconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) {
        timer.cancel();
        done();
      } else {
        if (mounted) {
          setState(() => _seconds--);
        }
      }
    });
  }

  void _showCheckin({bool fromImpact = false}) {
    if (!mounted) return;
    setState(() {
      _checking = true;
    });
    _notifications.triggerLockScreenCheckin(
      secondsRemaining: MokgosiConfig.checkinSeconds,
      impactG: fromImpact ? _telemetry.peakGForce : null,
    );
    _count(
      MokgosiConfig.checkinSeconds,
      () => _send(
        _telemetry.peakGForce >= MokgosiConfig.impactThresholdG
            ? 'MISSED_CHECKIN'
            : 'MISSED_CHECKIN',
        impactG: _telemetry.peakGForce,
      ),
    );
  }

  void _extendEscortFiveMinutes() {
    _timer?.cancel();
    _pinGuard.resetAttempts();
    _notifications.cancelCheckinAlert();
    const extensionSeconds = 300;
    setState(() {
      _checking = false;
      _active = true;
      _activeEscortTotalSeconds = extensionSeconds;
      _message = 'Walk extended by 5 minutes.';
    });
    _count(extensionSeconds, _showCheckin);
  }

  void _simulateImpactTrigger() {
    _telemetry.simulateImpact(
      simulatedG: 4.2,
      onImpactThreshold: (_) {
        if (!_active) {
          setState(() => _active = true);
        }
        _showCheckin(fromImpact: true);
      },
    );
  }

  Future<void> _send(
    String trigger, {
    double impactG = 1.0,
    bool covert = false,
  }) async {
    _timer?.cancel();
    unawaited(_notifications.cancelCheckinAlert());
    if (!covert && mounted) {
      setState(() {
        _sending = true;
        _message = 'Sending…';
      });
    }

    final fix = await _telemetry.resolveCurrentFix(
      pinToGaboroneDemoCbd: _profile.pinToGaboroneDemoCbd,
    );
    final outcome = await IncidentApi.trigger(
      trigger,
      impactG: impactG,
      lat: fix.lat,
      lng: fix.lng,
      userId: _profile.userId,
      trustedContactPhone: _profile.trustedContactPhone,
      category: _profile.category,
    );
    final queued = await IncidentApi.getQueuedEvents();

    if (outcome.incidentId != null && outcome.incidentId!.isNotEmpty) {
      _activeIncidentId = outcome.incidentId;
      _telemetry.startLiveLocationStream(
        pinToGaboroneDemoCbd: _profile.pinToGaboroneDemoCbd,
        onLocationUpdate: (liveFix) {
          IncidentApi.appendLocation(
            incidentId: outcome.incidentId!,
            lat: liveFix.lat,
            lng: liveFix.lng,
            capturedAtUtc: liveFix.capturedAtUtc,
          );
        },
      );
      if (_profile.consentAudio) {
        unawaited(
          IncidentApi.uploadConsentingAudioClip(
            incidentId: outcome.incidentId!,
            userConsented: _profile.consentAudio,
          ),
        );
      }
    }

    if (!covert && mounted) {
      setState(() {
        _sending = false;
        _checking = false;
        _queuedCount = queued.length;
        _message = outcome.userMessage;
      });
    }
  }

  void _handlePinSubmission({required bool endEscortOnSafe}) {
    final value = _pinController.text.trim();
    _pinController.clear();
    final outcome = _pinGuard.evaluate(value);

    switch (outcome) {
      case PinOutcome.safe:
        _timer?.cancel();
        _notifications.cancelCheckinAlert();
        _telemetry.resetPeakG();
        if (endEscortOnSafe) {
          _notifications.stopEscortForegroundService();
          _telemetry.stopMonitoring();
          setState(() {
            _active = false;
            _checking = false;
            _seconds = 0;
            _message = 'Walk ended. Glad you got there.';
          });
        } else {
          setState(() {
            _checking = false;
            _message = 'Checked in. The walk continues.';
          });
          _startEscort();
        }
        break;
      case PinOutcome.duress:
      case PinOutcome.duressThreeStrikes:
        _timer?.cancel();
        _notifications.cancelCheckinAlert();
        // Keep foreground service and location telemetry alive covertly;
        // never write duress text to state, and replace navigation stack so back is blocked.
        unawaited(_send('DURESS_PIN', impactG: _telemetry.peakGForce, covert: true));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const DecoySafeScreen()),
          (_) => false,
        );
        break;
      case PinOutcome.invalid:
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN not recognized')),
        );
        break;
    }
  }

  Future<void> _flushOfflineQueueNow() async {
    final flushed = await IncidentApi.flushOfflineQueue();
    final remaining = await IncidentApi.getQueuedEvents();
    if (!mounted) return;
    setState(() {
      _queuedCount = remaining.length;
      if (flushed > 0) {
        _message = flushed == 1 ? 'Sent the alert that was waiting.' : 'Sent $flushed alerts that were waiting.';
      }
    });
  }

  String _trustedContactSummary() {
    final phone = _profile.trustedContactPhone.trim();
    if (phone.isEmpty) {
      return 'No trusted contact yet. Add one in Settings.';
    }
    final name = _profile.trustedContactName.trim();
    return name.isNotEmpty
        ? 'Your alerts go to $name, ${formatPhone(phone)}.'
        : 'Your alerts go to ${formatPhone(phone)}.';
  }

  String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final seconds = _profile.escortDurationSeconds;
    final startLabel = seconds < 60 ? 'Start a $seconds-second walk' : 'Start a ${(seconds / 60).round()}-minute walk';
    final idle = !_active && !_checking;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mokgosi'),
        actions: <Widget>[
          if (MokgosiConfig.demoMode || widget.initialDemoControlsOpen)
            TextButton(
              key: const Key('toggle_rehearsal_controls_button'),
              onPressed: () => setState(() => _showDemoDrawer = !_showDemoDrawer),
              child: Text(_showDemoDrawer ? 'Hide demo tools' : 'Demo tools'),
            ),
          IconButton(
            key: const Key('open_safety_setup_button'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SafetySetupScreen(
                    profile: _profile,
                    pinGuard: _pinGuard,
                    onSaved: () {
                      _persistProfile();
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: <Widget>[
            if (_queuedCount > 0) ...<Widget>[
              _queueNotice(),
              const SizedBox(height: 12),
            ],
            if (_checking)
              CheckinPromptCard(
                secondsRemaining: _seconds,
                pinController: _pinController,
                impactGForce: _telemetry.peakGForce,
                wrongAttempts: _pinGuard.consecutiveWrongAttempts,
                onConfirmContinue: () => _handlePinSubmission(endEscortOnSafe: false),
                onConfirmEndEscort: () => _handlePinSubmission(endEscortOnSafe: true),
                onExtendFiveMinutes: _extendEscortFiveMinutes,
              )
            else if (_active)
              _activeWalkCard()
            else
              _startWalkCard(startLabel),
            if (idle && _message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _message,
                key: const Key('status_message_text'),
                style: const TextStyle(color: MokgosiColors.inkMuted, fontSize: 14, height: 1.4),
              ),
            ],
            if (idle) ...<Widget>[
              const SizedBox(height: 16),
              _situationCard(),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('send_sos_button'),
              style: FilledButton.styleFrom(
                backgroundColor: MokgosiColors.danger,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _sending ? null : () => _send('EXPLICIT_SOS', impactG: _telemetry.peakGForce),
              child: Text(_sending ? 'Sending…' : 'Send SOS', style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(height: 10),
            Text(
              _trustedContactSummary(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: MokgosiColors.inkMuted, fontSize: 13),
            ),
            if (_activeIncidentId != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Alert reference ${_activeIncidentId!.substring(0, 8)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MokgosiColors.inkFaint, fontSize: 12),
              ),
            ],
            if (_showDemoDrawer) ...<Widget>[
              const SizedBox(height: 20),
              _demoTools(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _queueNotice() {
    final waiting = _queuedCount == 1 ? '1 alert is' : '$_queuedCount alerts are';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: MokgosiColors.warningSoft,
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: Color(0xFFD9A441), width: 3)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$waiting waiting for a connection and will send on their own.',
              style: const TextStyle(color: MokgosiColors.warning, fontSize: 14),
            ),
          ),
          TextButton(
            key: const Key('flush_offline_queue_button'),
            onPressed: _flushOfflineQueueNow,
            child: const Text('Try now'),
          ),
        ],
      ),
    );
  }

  Widget _startWalkCard(String startLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Walking somewhere?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Start a timed walk. If you don’t check in before it ends, your trusted contact gets an alert with your location.',
              style: TextStyle(color: MokgosiColors.inkMuted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('start_escort_button'),
              onPressed: _sending ? null : () => _startEscort(),
              icon: const Icon(Icons.directions_walk),
              label: Text(startLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeWalkCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Walk in progress', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              _clock(_seconds),
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const Text('Check in before the timer runs out.', style: TextStyle(color: MokgosiColors.inkMuted)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (1 - (_seconds / _activeEscortTotalSeconds)).clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('checkin_now_button'),
              onPressed: _showCheckin,
              child: const Text('Check in now'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('request_end_escort_button'),
              onPressed: _showCheckin,
              child: const Text('I’ve arrived'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _situationCard() {
    final atHome = _profile.category == 'GBV_DOMESTIC';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionLabel('This is about'),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'PERSONAL_SAFETY', label: Text('Out and about')),
                ButtonSegment<String>(value: 'GBV_DOMESTIC', label: Text('At home')),
              ],
              selected: <String>{_profile.category},
              onSelectionChanged: (selection) {
                setState(() => _profile.category = selection.first);
                _persistProfile();
              },
            ),
            if (atHome) ...<Widget>[
              const SizedBox(height: 10),
              const InfoNote('Responders will treat your alerts as silent and won’t call this phone.'),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share my location when I raise an alert'),
              value: _profile.consentLocation,
              onChanged: (v) {
                setState(() => _profile.consentLocation = v);
                _persistProfile();
              },
            ),
            SwitchListTile(
              key: const Key('consent_audio_checkbox'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Record 15 seconds of sound after an alert'),
              subtitle: const Text('Optional. The alert goes out either way. Kept for 72 hours.'),
              value: _profile.consentAudio,
              onChanged: (v) {
                setState(() => _profile.consentAudio = v);
                _persistProfile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoTools() {
    return Card(
      color: MokgosiColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionLabel('Demo tools'),
            OutlinedButton(
              key: const Key('simulate_impact_button'),
              onPressed: _simulateImpactTrigger,
              child: const Text('Simulate a hard impact (4.2 g)'),
            ),
            SwitchListTile(
              key: const Key('simulate_offline_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pretend there’s no signal'),
              subtitle: const Text('Alerts queue up and the SMS app opens as a fallback.'),
              value: IncidentApi.simulateOfflineMode,
              onChanged: (val) {
                setState(() => IncidentApi.simulateOfflineMode = val);
                if (!val) _flushOfflineQueueNow();
              },
            ),
            const Text(
              'Demo PINs: 2580 to check in, 0852 is the duress PIN.',
              style: TextStyle(color: MokgosiColors.inkFaint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
