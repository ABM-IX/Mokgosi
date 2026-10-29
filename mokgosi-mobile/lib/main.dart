import 'package:flutter/material.dart';
import 'config/mokgosi_config.dart';
import 'config/theme.dart';
import 'screens/app_home_screen.dart';
import 'screens/escort_home.dart';
import 'screens/login_screen.dart';

export 'config/l10n.dart';
export 'config/mokgosi_config.dart';
export 'config/theme.dart';
export 'screens/app_home_screen.dart';
export 'screens/calculator_disguise_screen.dart';
export 'screens/checkin_prompt.dart';
export 'screens/consents_screen.dart';
export 'screens/decoy_safe_screen.dart';
export 'screens/escort_home.dart';
export 'screens/evidence_screen.dart';
export 'screens/get_help_screen.dart';
export 'screens/login_screen.dart';
export 'screens/pillar_selection_screen.dart';
export 'screens/safe_network_screen.dart';
export 'screens/safety_setup_screen.dart';
export 'screens/support_home.dart';
export 'services/incident_api.dart';
export 'services/motion_telemetry.dart';
export 'services/notification_guard.dart';

void main() => runApp(const MokgosiApp(requireAuth: true));

class MokgosiApp extends StatelessWidget {
  const MokgosiApp({
    super.key,
    this.home,
    this.requireAuth = false,
  });

  final Widget? home;
  final bool requireAuth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mokgosi',
      debugShowCheckedModeBanner: false,
      theme: buildMokgosiTheme(),
      home: home ?? (requireAuth ? const AuthGate() : const EscortHome()),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<String?> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = PlatformStore.read('auth_user_id');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final userId = snapshot.data;
        if (userId != null && userId.isNotEmpty) {
          return const AppHomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
