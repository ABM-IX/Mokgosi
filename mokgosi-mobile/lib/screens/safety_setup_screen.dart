import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import 'login_screen.dart';

/// Trusted Person & PIN configuration screen with E.164 phone validation,
/// salted SHA-256 PIN updates, and a survivor data-deletion action.
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
  String _currentUserId = 'MOKGOSI_DEMO_USER';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.trustedContactName);
    _phoneController = TextEditingController(text: widget.profile.trustedContactPhone);
    _safePinController = TextEditingController();
    _duressPinController = TextEditingController();
    _durationSeconds = widget.profile.escortDurationSeconds;
    _pinToGaboroneCbd = widget.profile.pinToGaboroneDemoCbd;
    _loadAuthInfo();
  }

  Future<void> _loadAuthInfo() async {
    final uid = await PlatformStore.read('auth_user_id');
    if (mounted && uid != null && uid.isNotEmpty) {
      setState(() => _currentUserId = uid);
    }
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
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !MokgosiConfig.isValidE164(phone)) {
      setState(() {
        _errorMessage = 'Trusted contact phone must use E.164 format (e.g. +2677xxxxxxx).';
      });
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
      _statusMessage =
          'Personal contact & session data cleared. Append-only forensic manifests remain sealed.';
    });
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety & Trusted Contact Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text(
              'Trusted Person Escalation (Route 1)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Only configure a number after obtaining the contact’s consent.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('trusted_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Trusted Person Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('trusted_phone_field'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Trusted Person Phone (E.164)',
                hintText: '+267...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Update Safe & Covert Duress PINs (4 digits, must differ)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('setup_safe_pin_field'),
                    controller: _safePinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'New Safe PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
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
                    decoration: const InputDecoration(
                      labelText: 'New Duress PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _durationSeconds,
              decoration: const InputDecoration(
                labelText: 'Escort Timer Duration',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 30, child: Text('30 seconds (demo)')),
                DropdownMenuItem(value: 300, child: Text('5 minutes')),
                DropdownMenuItem(value: 900, child: Text('15 minutes')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _durationSeconds = val);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pin GPS to Gaborone CBD Camera Mesh (Demo)'),
              subtitle: const Text(
                'Uses -24.6560, 25.9090 to match seeded 150m PostGIS cameras when indoor/emulator GPS is unavailable.',
              ),
              value: _pinToGaboroneCbd,
              onChanged: (v) => setState(() => _pinToGaboroneCbd = v),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xffff7676), fontWeight: FontWeight.w600),
              ),
            ],
            if (_statusMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Color(0xff55d9ad)),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('save_safety_setup_button'),
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('SAVE CONFIGURATION'),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('delete_personal_data_button'),
              onPressed: _deleteMyData,
              icon: const Icon(Icons.delete_outline, color: Color(0xffff7676)),
              label: const Text('Delete My Personal Data'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('btn_sign_out'),
              onPressed: () => LoginScreen.signOut(context),
              icon: const Icon(Icons.logout, color: Color(0xff94a3b8)),
              label: Text('Sign Out ($_currentUserId)'),
            ),
          ],
        ),
      ),
    );
  }
}
