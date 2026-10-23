import 'package:flutter/material.dart';
import 'screens/escort_home.dart';

export 'config/mokgosi_config.dart';
export 'screens/checkin_prompt.dart';
export 'screens/decoy_safe_screen.dart';
export 'screens/escort_home.dart';
export 'screens/safety_setup_screen.dart';
export 'services/incident_api.dart';
export 'services/motion_telemetry.dart';
export 'services/notification_guard.dart';

void main() => runApp(const MokgosiApp());

class MokgosiApp extends StatelessWidget {
  const MokgosiApp({super.key});

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
      home: const EscortHome(),
    );
  }
}
