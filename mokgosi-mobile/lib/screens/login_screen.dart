import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import 'app_home_screen.dart';

/// Citizen authentication & covert guest access screen for Mokgosi Mobile.
/// Supports standard credentials login, account registration, and a dedicated
/// private guest bypass to guarantee help can be requested even without an account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onAuthenticated,
  });

  final VoidCallback? onAuthenticated;

  /// Utility to log out the current citizen and return to the LoginScreen.
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

  // Sign In controllers
  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();

  // Sign Up controllers
  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPhoneController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signUpConfirmController = TextEditingController();

  bool _obscureSignInPassword = true;
  bool _obscureSignUpPassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      setState(() => _errorMessage = 'Please enter your email, phone, or citizen ID.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() => _isLoading = true);

    // Save session
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
    final phone = _signUpPhoneController.text.trim();
    final password = _signUpPasswordController.text;
    final confirm = _signUpConfirmController.text;

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a name or safe alias.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address.');
      return;
    }
    if (phone.isNotEmpty && !MokgosiConfig.isValidE164(phone)) {
      setState(() => _errorMessage = 'Phone number must use E.164 format (e.g. +2677xxxxxxx).');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);

    // Register & persist session
    await PlatformStore.write('auth_user_id', email);
    await PlatformStore.write('auth_display_name', name);
    await PlatformStore.write('auth_role', 'CITIZEN');
    if (phone.isNotEmpty) {
      await PlatformStore.write('auth_phone', phone);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _successMessage = 'Account created successfully!';
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
      MaterialPageRoute<void>(
        builder: (_) => const AppHomeScreen(initialTab: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff081421),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  // App Brand Banner
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xff12a879).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xff12a879), width: 1.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.shield,
                          size: 36,
                          color: Color(0xff12a879),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'MOKGOSI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your call for help. A connected response.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff94a3b8),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tab selector
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff0d1b2a),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff1e293b)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: const Color(0xff12a879),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xff94a3b8),
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      tabs: const [
                        Tab(key: Key('tab_sign_in'), text: 'Sign In'),
                        Tab(key: Key('tab_sign_up'), text: 'Create Account'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Error / Success message alert
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xff451a1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xffef4444)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xffef4444), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Color(0xfffca5a5), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xff064e3b),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff10b981)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Color(0xff10b981), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(color: Color(0xffa7f3d0), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Tab View contents
                  SizedBox(
                    height: 310,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSignInForm(),
                        _buildSignUpForm(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: Color(0xff1e293b)),
                  const SizedBox(height: 12),

                  // Emergency / Covert Guest Bypass Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff0d1624),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.shield_outlined, color: Color(0xff38b2ac), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Private / Immediate Danger Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Need covert access without saving credentials or an account history on this device?',
                          style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('btn_guest_access'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff38b2ac),
                            side: const BorderSide(color: Color(0xff38b2ac)),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isLoading ? null : _handleGuestEmergencyAccess,
                          icon: const Icon(Icons.bolt, size: 18),
                          label: const Text(
                            'Quick Emergency Access (No Account)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
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

  Widget _buildSignInForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('login_email_field'),
          controller: _signInEmailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Email or Citizen ID',
            labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 13),
            prefixIcon: const Icon(Icons.person_outline, color: Color(0xff94a3b8), size: 20),
            filled: true,
            fillColor: const Color(0xff0d1b2a),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff1e293b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff12a879)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('login_password_field'),
          controller: _signInPasswordController,
          obscureText: _obscureSignInPassword,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 13),
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xff94a3b8), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSignInPassword ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xff94a3b8),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureSignInPassword = !_obscureSignInPassword),
            ),
            filled: true,
            fillColor: const Color(0xff0d1b2a),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff1e293b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff12a879)),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: const Color(0xff12a879),
                      onChanged: (val) => setState(() => _rememberMe = val ?? true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Remember me',
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _autofillDemo,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Text(
                  'Demo Auto-fill',
                  style: TextStyle(
                    color: Color(0xff55d9ad),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        ElevatedButton(
          key: const Key('btn_sign_in_submit'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff12a879),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isLoading ? null : _handleSignIn,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSignUpForm() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          key: const Key('signup_name_field'),
          controller: _signUpNameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Display Name or Safe Alias',
            hintText: 'e.g. Mpho (Alias for GBV privacy)',
            labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xff0d1b2a),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff1e293b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff12a879)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('signup_email_field'),
          controller: _signUpEmailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xff0d1b2a),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff1e293b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff12a879)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('signup_phone_field'),
          controller: _signUpPhoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Phone Number (E.164 optional)',
            hintText: '+267 71 234 567',
            labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xff0d1b2a),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff1e293b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xff12a879)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('signup_password_field'),
                controller: _signUpPasswordController,
                obscureText: _obscureSignUpPassword,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xff0d1b2a),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xff1e293b)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xff12a879)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('signup_confirm_password_field'),
                controller: _signUpConfirmController,
                obscureText: _obscureSignUpPassword,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Confirm',
                  labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xff0d1b2a),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xff1e293b)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xff12a879)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          key: const Key('btn_sign_up_submit'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff12a879),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isLoading ? null : _handleSignUp,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
