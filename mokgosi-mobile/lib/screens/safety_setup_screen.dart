import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// Trusted contact for walks, the two PINs, walk length, and clearing this phone.
class SafetySetupScreen extends StatefulWidget {
  const SafetySetupScreen({
    super.key,
    required this.profile,
    required this.pinGuard,
    required this.onSaved,
  });

  final SafetyProfile profile;
  final PinGuard pinGuard;
  final VoidCallback onSaved;

  @override
  State<SafetySetupScreen> createState() => _SafetySetupScreenState();
}

class _SafetySetupScreenState extends State<SafetySetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _safePinController;
  late final TextEditingController _duressPinController;
  late int _durationSeconds;
  late bool _pinToGaboroneCbd;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.trustedContactName);
    _phoneController = TextEditingController(text: widget.profile.trustedContactPhone);
    _safePinController = TextEditingController();
    _duressPinController = TextEditingController();
    _durationSeconds = widget.profile.escortDurationSeconds;
    _pinToGaboroneCbd = widget.profile.pinToGaboroneDemoCbd;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _safePinController.dispose();
    _duressPinController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
    });
    final phone = _phoneController.text.replaceAll(' ', '').trim();
    if (phone.isNotEmpty && !MokgosiConfig.isValidE164(phone)) {
      setState(() => _errorMessage = 'Use the full number with the country code, like +267 71 234 567.');
      return;
    }

    final safeInput = _safePinController.text.trim();
    final duressInput = _duressPinController.text.trim();
    if (safeInput.isNotEmpty || duressInput.isNotEmpty) {
      final pinError = PinGuard.validatePinPair(safeInput, duressInput);
      if (pinError != null) {
        setState(() => _errorMessage = pinError);
        return;
      }
      widget.pinGuard.updatePins(safePin: safeInput, duressPin: duressInput);
    }

    widget.profile.trustedContactName = _nameController.text.trim();
    widget.profile.trustedContactPhone = phone;
    widget.profile.escortDurationSeconds = _durationSeconds;
    widget.profile.pinToGaboroneDemoCbd = _pinToGaboroneCbd;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  Future<void> _deleteMyData() async {
    await IncidentApi.requestPersonalDataDeletion(userId: widget.profile.userId);
    widget.profile.trustedContactName = '';
    widget.profile.trustedContactPhone = '';
    if (!mounted) return;
    setState(() {
      _nameController.clear();
      _phoneController.clear();
      _statusMessage = 'Cleared from this phone.';
    });
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: <Widget>[
            const SectionLabel('Trusted contact for walks'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Ask them first. They get a text if you miss a check-in or raise an alert.',
                      style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('trusted_name_field'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('trusted_phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+267 7X XXX XXX'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('PINs'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Your safe PIN ends a walk or answers a check-in. Your duress PIN looks exactly the same on screen but quietly raises an alert. Use 4 digits, and make them different.',
                      style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const Key('setup_safe_pin_field'),
                            controller: _safePinController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            decoration: const InputDecoration(labelText: 'New safe PIN', counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const Key('setup_duress_pin_field'),
                            controller: _duressPinController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            decoration: const InputDecoration(labelText: 'New duress PIN', counterText: ''),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Walks'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DropdownButtonFormField<int>(
                      initialValue: _durationSeconds,
                      decoration: const InputDecoration(labelText: 'How long before the first check-in'),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem(value: 30, child: Text('30 seconds (demo)')),
                        DropdownMenuItem(value: 300, child: Text('5 minutes')),
                        DropdownMenuItem(value: 900, child: Text('15 minutes')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _durationSeconds = val);
                      },
                    ),
                    if (MokgosiConfig.demoMode)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use the Gaborone CBD test location'),
                        subtitle: const Text('Demo only. Alerts report -24.6560, 25.9090 instead of your real location.'),
                        value: _pinToGaboroneCbd,
                        onChanged: (v) => setState(() => _pinToGaboroneCbd = v),
                      ),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              InfoNote(_errorMessage!, tone: NoteTone.danger),
            ],
            if (_statusMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              InfoNote(_statusMessage!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('save_safety_setup_button'),
              onPressed: _save,
              child: const Text('Save'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('delete_personal_data_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MokgosiColors.danger,
                side: const BorderSide(color: MokgosiColors.danger),
              ),
              onPressed: _deleteMyData,
              child: const Text('Clear my details from this phone'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('btn_sign_out'),
              onPressed: () => LoginScreen.signOut(context),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
