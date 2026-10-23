import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import '../services/motion_telemetry.dart';
import '../services/notification_guard.dart';
import 'checkin_prompt.dart';
import 'decoy_safe_screen.dart';
import 'safety_setup_screen.dart';

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
  String _message = 'Your call for help. A connected response.';

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
        _profile.pinToGaboroneDemoCbd = map['pin_to_gaborone_demo_cbd'] != false;
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
      _message = 'Escort extended by 5 minutes.';
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
        _message = 'Sending alert…';
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
            _message = 'Home safe confirmed. Escort ended.';
          });
        } else {
          setState(() {
            _checking = false;
            _message = 'Check-in confirmed. Continuing escort.';
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
        _message = 'Delivered $flushed queued offline alert(s).';
      }
    });
  }

  String _trustedContactSummary() {
    if (_profile.trustedContactPhone.trim().isEmpty) {
      return 'Trusted person · Not configured (tap gear to set up)';
    }
    final label = _profile.trustedContactName.trim().isNotEmpty
        ? '${_profile.trustedContactName.trim()} (${_profile.trustedContactPhone.trim()})'
        : _profile.trustedContactPhone.trim();
    return 'Trusted person · $label';
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _profile.escortDurationSeconds == 30
        ? 'START 30 SECOND ESCORT'
        : 'START ${(_profile.escortDurationSeconds / 60).round()} MINUTE ESCORT';

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('MOKGOSI'),
            Text(
              'PERSONAL SAFETY & RESPONSE NETWORK',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('toggle_rehearsal_controls_button'),
            tooltip: 'Demo & Rehearsal Controls',
            icon: Icon(
              _showDemoDrawer ? Icons.science : Icons.science_outlined,
              color: _showDemoDrawer ? const Color(0xff55d9ad) : Colors.white70,
            ),
            onPressed: () => setState(() => _showDemoDrawer = !_showDemoDrawer),
          ),
          IconButton(
            key: const Key('open_safety_setup_button'),
            tooltip: 'Trusted Person & PIN Setup',
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
          padding: const EdgeInsets.all(22),
          children: <Widget>[
            const SizedBox(height: 8),
            const Icon(Icons.shield_outlined, size: 68, color: Color(0xff55d9ad)),
            const SizedBox(height: 14),
            Text(
              _active ? 'ESCORT ACTIVE' : 'YOU ARE IN CONTROL',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21),
            ),
            const SizedBox(height: 10),
            Text(
              _active ? 'Check-in in $_seconds seconds' : _message,
              key: const Key('status_message_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (_queuedCount > 0) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: const Color(0xff3a2a14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.cloud_off, color: Color(0xffffc470), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Offline queue: $_queuedCount alert(s) waiting for signal.',
                          style: const TextStyle(color: Color(0xffffe2b0), fontSize: 12),
                        ),
                      ),
                      TextButton(
                        key: const Key('flush_offline_queue_button'),
                        onPressed: _flushOfflineQueueNow,
                        child: const Text('RETRY NOW'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (!_active && !_checking) _buildCategoryAndConsentCard(),
            if (_active) ...<Widget>[
              LinearProgressIndicator(
                value: (1 - (_seconds / _activeEscortTotalSeconds)).clamp(0.0, 1.0),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 18),
            ],
            if (!_active && !_checking)
              FilledButton.icon(
                key: const Key('start_escort_button'),
                onPressed: _sending ? null : () => _startEscort(),
                icon: const Icon(Icons.directions_walk),
                label: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(startLabel),
                ),
              ),
            if (_active && !_checking) ...<Widget>[
              OutlinedButton(
                key: const Key('checkin_now_button'),
                onPressed: _showCheckin,
                child: const Text('CHECK IN NOW'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                key: const Key('request_end_escort_button'),
                onPressed: _showCheckin,
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text("I'M HOME SAFE — END ESCORT (PIN REQUIRED)"),
              ),
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
              ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              key: const Key('send_sos_button'),
              onPressed: _sending
                  ? null
                  : () => _send('EXPLICIT_SOS', impactG: _telemetry.peakGForce),
              icon: const Icon(Icons.sos, color: Colors.redAccent),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('SEND SOS'),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _trustedContactSummary(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            if (_activeIncidentId != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Active Incident Ref: ${_activeIncidentId!.substring(0, 8)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xff55d9ad), fontSize: 12),
              ),
            ],
            if (_showDemoDrawer) ...<Widget>[
              const SizedBox(height: 18),
              _buildDemoRehearsalPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryAndConsentCard() {
    final isGbv = _profile.category == 'GBV_DOMESTIC';
    return Card(
      color: const Color(0xff0f2033),
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'PROTECTION CONTEXT & SURVIVOR CONSENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xff55d9ad),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'PERSONAL_SAFETY',
                  label: Text('Commute / Safety', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.directions_walk, size: 16),
                ),
                ButtonSegment<String>(
                  value: 'GBV_DOMESTIC',
                  label: Text('Unsafe at Home / Partner', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.privacy_tip_outlined, size: 16),
                ),
              ],
              selected: <String>{_profile.category},
              onSelectionChanged: (selection) {
                setState(() => _profile.category = selection.first);
                _persistProfile();
              },
            ),
            if (isGbv) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'GBV / Domestic mode flags responder console for covert handling (no callbacks to device on duress).',
                style: TextStyle(color: Color(0xffffc470), fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Share live GPS & match authorized 150m cameras on alert',
                style: TextStyle(fontSize: 12),
              ),
              value: _profile.consentLocation,
              onChanged: (v) {
                setState(() => _profile.consentLocation = v ?? true);
                _persistProfile();
              },
            ),
            CheckboxListTile(
              key: const Key('consent_audio_checkbox'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Consent to 15s post-alert acoustic triage clip (72h retention)',
                style: TextStyle(fontSize: 12),
              ),
              subtitle: const Text(
                'Optional escalation aid only; declining never blocks your SOS.',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              value: _profile.consentAudio,
              onChanged: (v) {
                setState(() => _profile.consentAudio = v ?? false);
                _persistProfile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoRehearsalPanel() {
    return Card(
      color: const Color(0xff132436),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'DEMO & FAULT-TOLERANCE REHEARSAL CONTROLS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xff55d9ad),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('simulate_impact_button'),
              onPressed: _simulateImpactTrigger,
              icon: const Icon(Icons.vibration, size: 18),
              label: Text(
                'Simulate Physical Impact (4.2g · Peak ${_telemetry.peakGForce.toStringAsFixed(1)}g)',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('simulate_offline_switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Simulate Airplane / Offline Mode',
                style: TextStyle(fontSize: 12),
              ),
              subtitle: const Text(
                'Queues SOS with idempotency UUID & fires SMS fallback',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              value: IncidentApi.simulateOfflineMode,
              onChanged: (val) {
                setState(() => IncidentApi.simulateOfflineMode = val);
                if (!val) {
                  _flushOfflineQueueNow();
                }
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'DEMO ONLY PINs: Safe 2580 · Covert Duress 0852',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
