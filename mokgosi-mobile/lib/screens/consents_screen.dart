import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import 'calculator_disguise_screen.dart';

class ConsentsScreen extends StatefulWidget {
  const ConsentsScreen({super.key, this.userId = 'MOKGOSI_DEMO_USER'});

  final String userId;

  @override
  State<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends State<ConsentsScreen> {
  bool _locationConsent = true;
  bool _audioConsent = false;
  bool _responderContactConsent = false;
  bool _shareEvidenceConsent = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadConsents();
  }

  Future<void> _loadConsents() async {
    setState(() => _isLoading = true);
    final data = await IncidentApi.fetchConsents(widget.userId);
    if (mounted) {
      setState(() {
        _locationConsent = data['location'] ?? true;
        _audioConsent = data['audio'] ?? false;
        _responderContactConsent = data['responder_contact'] ?? false;
        _shareEvidenceConsent = data['share_evidence'] ?? false;
        _isLoading = false;
      });
    }
  }

  void _quickExit() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CalculatorDisguiseScreen()),
      (route) => false,
    );
  }

  Future<void> _saveConsents() async {
    setState(() => _isSaving = true);
    final success = await IncidentApi.updateConsents(
      userId: widget.userId,
      location: _locationConsent,
      audio: _audioConsent,
      responderContact: _responderContactConsent,
      shareEvidence: _shareEvidenceConsent,
    );
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Consents updated securely.' : 'Failed to update consents on server.'),
          backgroundColor: success ? const Color(0xff319795) : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _purgeAllData() async {
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1a202c),
        title: const Text('Remove All Mokgosi Data?', style: TextStyle(color: Color(0xfffc8181))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will immediately purge all local encrypted evidence, safe network contacts, and cache from this phone, and request server deletion of your profile.',
              style: TextStyle(color: Color(0xffcbd5e0), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your Safe PIN to confirm:',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('purge_pin_field'),
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'PIN',
                hintStyle: TextStyle(color: Color(0xff718096)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xff4a5568))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            key: const Key('confirm_purge_button'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffe53e3e)),
            onPressed: () {
              if (pinController.text == MokgosiConfig.safePin) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect PIN.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Purge Everything', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await PlatformStore.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const CalculatorDisguiseScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xff161b22),
        title: Text(MokgosiL10n.get('consents'), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            key: const Key('consents_quick_exit'),
            tooltip: MokgosiL10n.get('quick_exit'),
            icon: const Icon(Icons.close_fullscreen, color: Color(0xfffc8181)),
            onPressed: _quickExit,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff161b22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff30363d)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: Color(0xff4fd1c5), size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Survivor-Owned Control: You decide what data is collected. Audio recording and responder direct contact are disabled by default.',
                            style: TextStyle(color: Color(0xffcbd5e0), fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Location Switch
                  _buildConsentTile(
                    title: 'Location Transmission During Alert',
                    description: 'Sends coarse or exact GPS to your safe network and responders only when an active SOS is dispatched.',
                    value: _locationConsent,
                    onChanged: (val) => setState(() => _locationConsent = val),
                  ),
                  const Divider(color: Color(0xff21262d), height: 24),
                  // Audio Switch
                  _buildConsentTile(
                    title: 'Audio Capture in Background (Default: OFF)',
                    description: 'Allows recording ambient audio clips for survivor-owned cryptographic evidence. Audio is encrypted and never uploaded without explicit consent.',
                    value: _audioConsent,
                    onChanged: (val) => setState(() => _audioConsent = val),
                  ),
                  const Divider(color: Color(0xff21262d), height: 24),
                  // Responder Contact Switch
                  _buildConsentTile(
                    title: 'Responder Direct Contact (Default: OFF)',
                    description: 'Allows command center responders to call or SMS you after an alert. Note: Under DURESS or COVERT alerts, this is always overridden to NEVER contact to protect your safety.',
                    value: _responderContactConsent,
                    onChanged: (val) => setState(() => _responderContactConsent = val),
                  ),
                  const Divider(color: Color(0xff21262d), height: 24),
                  // Share Evidence Switch
                  _buildConsentTile(
                    title: 'Share Evidence with Authorized Partners',
                    description: 'Permits creating verified case bundles for legal aid, police GBV desks, or medical examiners upon your explicit manual request.',
                    value: _shareEvidenceConsent,
                    onChanged: (val) => setState(() => _shareEvidenceConsent = val),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    key: const Key('save_consents_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff319795),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSaving ? null : _saveConsents,
                    child: _isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Consent Preferences', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 32),
                  // Purge Data Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xff2d1515),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xffe53e3e)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Emergency Local Purge',
                          style: TextStyle(color: Color(0xfffc8181), fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'If you feel your phone is being searched or monitored, you can immediately erase all cached safe network data, evidence, and tokens.',
                          style: TextStyle(color: Color(0xfffed7d7), fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key('purge_data_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xfffc8181),
                            side: const BorderSide(color: Color(0xffe53e3e)),
                          ),
                          onPressed: _purgeAllData,
                          icon: const Icon(Icons.delete_forever, size: 18),
                          label: const Text('Remove All Mokgosi Data From Phone'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildConsentTile({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(color: Color(0xffa0aec0), fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          activeThumbColor: const Color(0xff38b2ac),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
