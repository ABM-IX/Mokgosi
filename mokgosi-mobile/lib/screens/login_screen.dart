import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../widgets/common.dart';
import 'app_home_screen.dart';

/// Sign in, create an account, or continue without one.
///
/// Note: nothing here is checked against a server yet. Pre-deploy item 3 replaces this screen with
/// an anonymous first-run setup.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onAuthenticated,
    this.showDemoFill = MokgosiConfig.demoMode,
  });

  final VoidCallback? onAuthenticated;
  final bool showDemoFill;

  /// Signs the current person out and returns to this screen.
  static Future<void> signOut(BuildContext context) async {
    await PlatformStore.write('auth_user_id', null);
    await PlatformStore.write('auth_display_name', null);
    await PlatformStore.write('auth_role', null);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPhoneController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signUpConfirmController = TextEditingController();

  bool _obscureSignInPassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() => _errorMessage = null));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPhoneController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
    final email = _signInEmailController.text.trim();
    final password = _signInPasswordController.text;
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter your password.');
      return;
    }

    setState(() => _isLoading = true);
    await PlatformStore.write('auth_user_id', email);
    await PlatformStore.write('auth_display_name', email.split('@').first);
    await PlatformStore.write('auth_role', 'CITIZEN');
    if (!mounted) return;
    setState(() => _isLoading = false);
    _proceedToApp();
  }

  Future<void> _handleSignUp() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
    final name = _signUpNameController.text.trim();
    final email = _signUpEmailController.text.trim();
    final phone = _signUpPhoneController.text.replaceAll(' ', '').trim();
    final password = _signUpPasswordController.text;
    final confirm = _signUpConfirmController.text;

    String? problem;
    if (name.isEmpty) {
      problem = 'Enter a name or nickname.';
    } else if (email.isEmpty) {
      problem = 'Enter your email address.';
    } else if (phone.isNotEmpty && !MokgosiConfig.isValidE164(phone)) {
      problem = 'Use the full number with the country code, like +267 71 234 567.';
    } else if (password.length < 6) {
      problem = 'Use at least 6 characters for your password.';
    } else if (password != confirm) {
      problem = 'The passwords don’t match.';
    }
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return;
    }

    setState(() => _isLoading = true);
    await PlatformStore.write('auth_user_id', email);
    await PlatformStore.write('auth_display_name', name);
    await PlatformStore.write('auth_role', 'CITIZEN');
    if (phone.isNotEmpty) {
      await PlatformStore.write('auth_phone', phone);
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _successMessage = 'Account created.';
    });
    _proceedToApp();
  }

  Future<void> _handleGuestEmergencyAccess() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    final guestId = 'GUEST_${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    await PlatformStore.write('auth_user_id', guestId);
    await PlatformStore.write('auth_display_name', 'Anonymous Guest');
    await PlatformStore.write('auth_role', 'GUEST');
    if (!mounted) return;
    setState(() => _isLoading = false);
    _proceedToApp();
  }

  void _autofillDemo() {
    setState(() {
      _signInEmailController.text = 'citizen@mokgosi.org';
      _signInPasswordController.text = 'demo-pass-2026';
      _errorMessage = null;
    });
  }

  void _proceedToApp() {
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppHomeScreen(initialTab: 0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Mokgosi', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'Your call for help. A connected response.',
                    style: TextStyle(color: MokgosiColors.inkMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          controller: _tabController,
                          tabs: const [
                            Tab(key: Key('tab_sign_in'), text: 'Sign in'),
                            Tab(key: Key('tab_sign_up'), text: 'Create account'),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: AnimatedBuilder(
                            animation: _tabController,
                            builder: (_, __) => _tabController.index == 0 ? _buildSignInForm() : _buildSignUpForm(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Need help right now?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          const Text(
                            'Use Mokgosi without an account. No account details are saved on this phone.',
                            style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            key: const Key('btn_guest_access'),
                            onPressed: _isLoading ? null : _handleGuestEmergencyAccess,
                            child: const Text('Continue without an account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _messages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[InfoNote(_errorMessage!, tone: NoteTone.danger), const SizedBox(height: 12)],
        if (_successMessage != null) ...[InfoNote(_successMessage!), const SizedBox(height: 12)],
      ],
    );
  }

  Widget _buildSignInForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _messages(),
        TextField(
          key: const Key('login_email_field'),
          controller: _signInEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('login_password_field'),
          controller: _signInPasswordController,
          obscureText: _obscureSignInPassword,
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              tooltip: _obscureSignInPassword ? 'Show password' : 'Hide password',
              icon: Icon(_obscureSignInPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscureSignInPassword = !_obscureSignInPassword),
            ),
          ),
        ),
        Row(
          children: [
            Checkbox(value: _rememberMe, onChanged: (v) => setState(() => _rememberMe = v ?? true)),
            const Expanded(child: Text('Keep me signed in')),
            if (widget.showDemoFill) TextButton(onPressed: _autofillDemo, child: const Text('Fill in demo details')),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('btn_sign_in_submit'),
          onPressed: _isLoading ? null : _handleSignIn,
          child: Text(_isLoading ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }

  Widget _buildSignUpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _messages(),
        TextField(
          key: const Key('signup_name_field'),
          controller: _signUpNameController,
          decoration: const InputDecoration(labelText: 'Name or nickname', helperText: 'It does not have to be your real name.'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('signup_email_field'),
          controller: _signUpEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('signup_phone_field'),
          controller: _signUpPhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile number (optional)', hintText: '+267 71 234 567'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('signup_password_field'),
                controller: _signUpPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('signup_confirm_password_field'),
                controller: _signUpConfirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('btn_sign_up_submit'),
          onPressed: _isLoading ? null : _handleSignUp,
          child: Text(_isLoading ? 'Creating…' : 'Create account'),
        ),
      ],
    );
  }
}
