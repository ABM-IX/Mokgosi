import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../services/motion_telemetry.dart';
import '../widgets/common.dart';
import 'calculator_disguise_screen.dart';
import 'consents_screen.dart';
import 'evidence_screen.dart';
import 'get_help_screen.dart';
import 'safe_network_screen.dart';

class SupportHome extends StatefulWidget {
  const SupportHome({super.key});

  @override
  State<SupportHome> createState() => _SupportHomeState();
}

class _SupportHomeState extends State<SupportHome> {
  final MotionTelemetry _telemetry = MotionTelemetry();
  // Off until the person turns it on: the detector only runs once switched on.
  bool _shakeEnabled = false;
  double _shakeSensitivity = 2.8;
  String? _silentAlertStatus;

  void _quickExit() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CalculatorDisguiseScreen()),
      (route) => false,
    );
  }

  Future<void> _sendCovertAlert(String trigger) async {
    // No sound, vibration or permission prompt: any of them would give the alert away.
    final fix = await _telemetry.resolveCurrentFix(
      pinToGaboroneDemoCbd: MokgosiConfig.demoMode,
      requestPermission: false,
    );
    final outcome = await IncidentApi.trigger(trigger, category: 'GBV_DOMESTIC', lat: fix.lat, lng: fix.lng);
    if (!mounted || trigger != 'COVERT_SOS') return;
    setState(() => _silentAlertStatus = outcome.delivered ? 'Sent' : 'Saved, will send when online');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _silentAlertStatus = null);
    });
  }

  @override
  void dispose() {
    _telemetry.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(MokgosiL10n.get('support_and_safety')),
        actions: [
          TextButton(
            key: const Key('lang_toggle_button'),
            onPressed: () => setState(() {
              MokgosiL10n.currentLocale = MokgosiL10n.currentLocale == 'en' ? 'tn' : 'en';
            }),
            child: Text(MokgosiL10n.currentLocale == 'en' ? 'Setswana' : 'English'),
          ),
          HideAction(key: const Key('support_quick_exit'), label: MokgosiL10n.get('quick_exit'), onPressed: _quickExit),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      MokgosiL10n.get('covert_sos'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Alerts your trusted contacts and responders without any sound or vibration. Responders will not call you.',
                      style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      key: const Key('silent_sos_button'),
                      style: FilledButton.styleFrom(backgroundColor: MokgosiColors.ink),
                      onPressed: _silentAlertStatus != null ? null : () => _sendCovertAlert('COVERT_SOS'),
                      child: Text(_silentAlertStatus ?? 'Send silent alert'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _navTile(
                    key: const Key('nav_safe_network'),
                    icon: Icons.people_outline,
                    title: MokgosiL10n.get('safe_network'),
                    subtitle: 'Up to five people, messaged in the order you choose',
                    screen: const SafeNetworkScreen(),
                  ),
                  const Divider(indent: 56),
                  _navTile(
                    key: const Key('nav_evidence'),
                    icon: Icons.edit_note_outlined,
                    title: MokgosiL10n.get('evidence_vault'),
                    subtitle: 'Notes kept on this phone until you choose to share them',
                    screen: const EvidenceScreen(),
                  ),
                  const Divider(indent: 56),
                  _navTile(
                    key: const Key('nav_get_help'),
                    icon: Icons.support_outlined,
                    title: MokgosiL10n.get('get_help'),
                    subtitle: 'Services that have confirmed their details',
                    screen: const GetHelpScreen(),
                  ),
                  const Divider(indent: 56),
                  _navTile(
                    key: const Key('nav_consents'),
                    icon: Icons.lock_outline,
                    title: MokgosiL10n.get('consents'),
                    subtitle: 'What is shared, and removing everything',
                    screen: const ConsentsScreen(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(MokgosiL10n.get('shake_sos_title')),
                      subtitle: const Text('Shake your phone hard three times within two seconds to send a silent alert.'),
                      value: _shakeEnabled,
                      onChanged: (val) {
                        setState(() => _shakeEnabled = val);
                        if (val) {
                          _telemetry.startShakeMonitoring(
                            thresholdG: _shakeSensitivity,
                            onShakeSos: () => _sendCovertAlert('SHAKE_SOS'),
                          );
                        } else {
                          _telemetry.stopMonitoring();
                        }
                      },
                    ),
                    Row(
                      children: [
                        const Text('Gentle', style: TextStyle(color: MokgosiColors.inkMuted, fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: _shakeSensitivity,
                            min: 2.0,
                            max: 4.5,
                            divisions: 5,
                            label: '${_shakeSensitivity.toStringAsFixed(1)} g',
                            onChanged: (val) => setState(() => _shakeSensitivity = val),
                          ),
                        ),
                        const Text('Firm', style: TextStyle(color: MokgosiColors.inkMuted, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
  }) {
    return ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }
}
