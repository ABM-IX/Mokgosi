import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../widgets/common.dart';
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
          content: Text(success ? 'Saved.' : 'Saved on this phone. It could not be sent to the server yet.'),
        ),
      );
    }
  }

  Future<void> _purgeAllData() async {
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This deletes your contacts, journal, settings and any waiting alerts from this phone straight away.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('purge_pin_field'),
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Your PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm_purge_button'),
            style: FilledButton.styleFrom(backgroundColor: MokgosiColors.danger),
            onPressed: () {
              if (pinController.text == MokgosiConfig.safePin) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That PIN didn’t match.')));
              }
            },
            child: const Text('Remove'),
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
      appBar: AppBar(
        title: Text(MokgosiL10n.get('consents')),
        actions: [
          HideAction(key: const Key('consents_quick_exit'), label: MokgosiL10n.get('quick_exit'), onPressed: _quickExit),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  const Text(
                    'You decide what Mokgosi shares. Sound recording and calls from responders stay off unless you turn them on.',
                    style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        children: [
                          _consentTile(
                            title: MokgosiL10n.get('location_consent'),
                            description: 'Your location goes to your trusted contacts and responders only while an alert is open.',
                            value: _locationConsent,
                            onChanged: (val) => setState(() => _locationConsent = val),
                          ),
                          const Divider(),
                          _consentTile(
                            title: MokgosiL10n.get('audio_consent'),
                            description: 'Records 15 seconds of sound to help responders understand what is happening. Off unless you turn it on.',
                            value: _audioConsent,
                            onChanged: (val) => setState(() => _audioConsent = val),
                          ),
                          const Divider(),
                          _consentTile(
                            title: MokgosiL10n.get('responder_contact_consent'),
                            description: 'Off unless you turn it on. Silent alerts always stay silent: responders will not call you then, whatever this is set to.',
                            value: _responderContactConsent,
                            onChanged: (val) => setState(() => _responderContactConsent = val),
                          ),
                          const Divider(),
                          _consentTile(
                            title: 'Let me share my journal',
                            description: 'Lets you create a link for a lawyer, the police or a counsellor. Nothing is shared until you pick the entries yourself.',
                            value: _shareEvidenceConsent,
                            onChanged: (val) => setState(() => _shareEvidenceConsent = val),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('save_consents_button'),
                    onPressed: _isSaving ? null : _saveConsents,
                    child: Text(_isSaving ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(height: 32),
                  const SectionLabel('If someone is going through your phone'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Remove everything Mokgosi has stored on this phone. Your copy on the server is not deleted from here yet.',
                            style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            key: const Key('purge_data_button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MokgosiColors.danger,
                              side: const BorderSide(color: MokgosiColors.danger),
                            ),
                            onPressed: _purgeAllData,
                            child: Text(MokgosiL10n.get('remove_data')),
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

  Widget _consentTile({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(description)),
      value: value,
      onChanged: onChanged,
    );
  }
}
