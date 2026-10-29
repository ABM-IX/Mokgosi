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
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          EscortHome(),
          SupportHome(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            key: const Key('tab_getting_around'),
            icon: const Icon(Icons.directions_walk_outlined),
            selectedIcon: const Icon(Icons.directions_walk),
            label: MokgosiL10n.get('getting_around'),
          ),
          NavigationDestination(
            key: const Key('tab_support_safety'),
            icon: const Icon(Icons.support_outlined),
            selectedIcon: const Icon(Icons.support),
            label: MokgosiL10n.get('support_and_safety'),
          ),
        ],
      ),
    );
  }
}
