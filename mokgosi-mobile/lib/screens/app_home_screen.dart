import 'package:flutter/material.dart';
import '../config/l10n.dart';
import 'escort_home.dart';
import 'support_home.dart';

class AppHomeScreen extends StatefulWidget {
  const AppHomeScreen({
    super.key,
    this.initialTab = 0,
  });

  final int initialTab;

  @override
  State<AppHomeScreen> createState() => _AppHomeScreenState();
}

class _AppHomeScreenState extends State<AppHomeScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff081421),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          EscortHome(),
          SupportHome(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: const Color(0xff0d1624),
        indicatorColor: const Color(0xff12a879).withValues(alpha: 0.25),
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            key: const Key('tab_getting_around'),
            icon: const Icon(Icons.directions_walk_outlined, color: Colors.white70),
            selectedIcon: const Icon(Icons.directions_walk, color: Color(0xff12a879)),
            label: MokgosiL10n.get('getting_around'),
          ),
          NavigationDestination(
            key: const Key('tab_support_safety'),
            icon: const Icon(Icons.shield_outlined, color: Colors.white70),
            selectedIcon: const Icon(Icons.shield, color: Color(0xff38b2ac)),
            label: MokgosiL10n.get('support_and_safety'),
          ),
        ],
      ),
    );
  }
}
