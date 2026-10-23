import 'package:flutter/material.dart';
import '../config/l10n.dart';
import 'app_home_screen.dart';

class PillarSelectionScreen extends StatefulWidget {
  const PillarSelectionScreen({super.key});

  @override
  State<PillarSelectionScreen> createState() => _PillarSelectionScreenState();
}

class _PillarSelectionScreenState extends State<PillarSelectionScreen> {
  bool _gettingAroundSelected = true;
  bool _supportSafetySelected = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff081421),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                MokgosiL10n.get('onboarding_question'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                MokgosiL10n.get('onboarding_subtitle'),
                style: const TextStyle(
                  color: Color(0xff94a3b8),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              // Option 1: Pillar A
              _buildOptionCard(
                key: const Key('pillar_a_checkbox'),
                icon: Icons.directions_walk,
                iconColor: const Color(0xff12a879),
                title: MokgosiL10n.get('getting_around'),
                subtitle: MokgosiL10n.get('getting_around_desc'),
                isSelected: _gettingAroundSelected,
                onTap: () {
                  setState(() => _gettingAroundSelected = !_gettingAroundSelected);
                },
              ),
              const SizedBox(height: 16),
              // Option 2: Pillar B
              _buildOptionCard(
                key: const Key('pillar_b_checkbox'),
                icon: Icons.shield_outlined,
                iconColor: const Color(0xff38b2ac),
                title: MokgosiL10n.get('support_and_safety'),
                subtitle: MokgosiL10n.get('support_and_safety_desc'),
                isSelected: _supportSafetySelected,
                onTap: () {
                  setState(() => _supportSafetySelected = !_supportSafetySelected);
                },
              ),
              const Spacer(),
              ElevatedButton(
                key: const Key('continue_onboarding_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff12a879),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  int startTab = 0;
                  if (!_gettingAroundSelected && _supportSafetySelected) {
                    startTab = 1;
                  }
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => AppHomeScreen(initialTab: startTab),
                    ),
                  );
                },
                child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xff0d1b2a),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? iconColor : const Color(0xff1e293b),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withValues(alpha: 0.15),
              radius: 22,
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Color(0xff94a3b8), fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            Checkbox(
              value: isSelected,
              activeColor: iconColor,
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}
