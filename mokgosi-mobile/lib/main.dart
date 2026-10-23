import 'package:flutter/material.dart';
import 'screens/escort_home.dart';

export 'config/l10n.dart';
export 'config/mokgosi_config.dart';
export 'screens/app_home_screen.dart';
export 'screens/calculator_disguise_screen.dart';
export 'screens/checkin_prompt.dart';
export 'screens/consents_screen.dart';
export 'screens/decoy_safe_screen.dart';
export 'screens/escort_home.dart';
export 'screens/evidence_screen.dart';
export 'screens/get_help_screen.dart';
export 'screens/pillar_selection_screen.dart';
export 'screens/safe_network_screen.dart';
export 'screens/safety_setup_screen.dart';
export 'screens/support_home.dart';
export 'services/incident_api.dart';
export 'services/motion_telemetry.dart';
export 'services/notification_guard.dart';

void main() => runApp(const MokgosiApp());

class MokgosiApp extends StatelessWidget {
  const MokgosiApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mokgosi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff12a879),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff081421),
        useMaterial3: true,
      ),
      home: home ?? const EscortHome(),
    );
  }
}
