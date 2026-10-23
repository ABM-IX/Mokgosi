import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../services/incident_api.dart';
import '../services/motion_telemetry.dart';
import 'calculator_disguise_screen.dart';
import 'consents_screen.dart';
import 'get_help_screen.dart';
import 'safe_network_screen.dart';

class SupportHome extends StatefulWidget {
  const SupportHome({super.key});

  @override
  State<SupportHome> createState() => _SupportHomeState();
}

class _SupportHomeState extends State<SupportHome> {
  bool _shakeEnabled = true;
  double _shakeSensitivity = 2.8;
  bool _silentAlertDispatched = false;

  void _quickExit() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CalculatorDisguiseScreen()),
      (route) => false,
    );
  }

  void _triggerSilentCovertSos() async {
    // Covert invariant: No sound, no vibration, no alert toast.
    await IncidentApi.trigger('COVERT_SOS', category: 'GBV_DOMESTIC');
    setState(() => _silentAlertDispatched = true);
    // After 2 seconds reset silently without visual drama
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _silentAlertDispatched = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xff161b22),
        title: Text(MokgosiL10n.get('support_and_safety'), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            key: const Key('lang_toggle_button'),
            tooltip: 'Language / Puo',
            icon: const Icon(Icons.translate, color: Color(0xff81e6d9)),
            onPressed: () {
              setState(() {
                MokgosiL10n.currentLocale = MokgosiL10n.currentLocale == 'en' ? 'tn' : 'en';
              });
            },
          ),
          IconButton(
            key: const Key('support_quick_exit'),
            tooltip: MokgosiL10n.get('quick_exit'),
            icon: const Icon(Icons.close_fullscreen, color: Color(0xfffc8181)),
            onPressed: _quickExit,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quick Exit Banner at top
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xff21262d),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff30363d)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xff4fd1c5), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pillar B: Survivor-Centred Safety & Support',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xfffc8181),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _quickExit,
                    icon: const Icon(Icons.exit_to_app, size: 16),
                    label: Text(MokgosiL10n.get('quick_exit'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Silent Trigger Tile
            Card(
              color: const Color(0xff161b22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xff30363d)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          MokgosiL10n.get('covert_sos'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xff742a2a).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xffe53e3e)),
                          ),
                          child: const Text('Silent / No Sound', style: TextStyle(color: Color(0xfffeb2b2), fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Silently escalates an alert through your Safe Network and Command Center without alarm or sound. Responders will follow silent protocol and never call you directly.',
                      style: TextStyle(color: Color(0xffa0aec0), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      key: const Key('silent_sos_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _silentAlertDispatched ? const Color(0xff2d3748) : const Color(0xff9b2c2c),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _silentAlertDispatched ? null : _triggerSilentCovertSos,
                      child: Text(
                        _silentAlertDispatched ? 'Dispatched Silently' : 'Send Silent Alert Now',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Menu Cards Grid
            _buildNavigationCard(
              key: const Key('nav_safe_network'),
              icon: Icons.people_outline,
              iconColor: const Color(0xff4fd1c5),
              title: MokgosiL10n.get('safe_network'),
              subtitle: 'Manage your trusted 5-contact escalation chain and priority',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SafeNetworkScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildNavigationCard(
              key: const Key('nav_get_help'),
              icon: Icons.support_agent,
              iconColor: const Color(0xff63b3ed),
              title: MokgosiL10n.get('get_help'),
              subtitle: 'Directory of verified GBV desks, shelters, and legal services',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GetHelpScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildNavigationCard(
              key: const Key('nav_consents'),
              icon: Icons.privacy_tip_outlined,
              iconColor: const Color(0xfff6ad55),
              title: MokgosiL10n.get('consents'),
              subtitle: 'Survivor-owned data controls, permissions, and emergency purge',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ConsentsScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            // Covert Triggers Settings
            Card(
              color: const Color(0xff161b22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xff30363d)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Background Covert Triggers',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Trigger silent alerts even when phone screen is locked or app is closed.',
                      style: TextStyle(color: Color(0xffa0aec0), fontSize: 12),
                    ),
                    const Divider(color: Color(0xff21262d), height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('3-Shake Gesture', style: TextStyle(color: Colors.white, fontSize: 14)),
                              Text('3 firm shakes within 2 seconds with 15s cooldown', style: TextStyle(color: Color(0xff718096), fontSize: 11)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _shakeEnabled,
                          activeThumbColor: const Color(0xff38b2ac),
                          onChanged: (val) {
                            setState(() => _shakeEnabled = val);
                            if (val) {
                              MotionTelemetry().startShakeMonitoring(
                                thresholdG: _shakeSensitivity,
                                onShakeSos: () => IncidentApi.trigger('SHAKE_SOS', category: 'GBV_DOMESTIC'),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Sensitivity: ', style: TextStyle(color: Color(0xffa0aec0), fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _shakeSensitivity,
                            min: 2.0,
                            max: 4.5,
                            divisions: 5,
                            activeColor: const Color(0xff319795),
                            label: '${_shakeSensitivity.toStringAsFixed(1)}g',
                            onChanged: (val) => setState(() => _shakeSensitivity = val),
                          ),
                        ),
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

  Widget _buildNavigationCard({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      key: key,
      color: const Color(0xff161b22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xff30363d)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.15),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xffa0aec0), fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xff718096)),
        onTap: onTap,
      ),
    );
  }
}
