import 'package:flutter/material.dart';
import '../config/theme.dart';

/// The 15-second "are you OK?" check during a walk. One PIN field serves both PINs, and nothing on
/// this card hints that a second PIN exists: someone may be watching the screen.
class CheckinPromptCard extends StatelessWidget {
  const CheckinPromptCard({
    super.key,
    required this.secondsRemaining,
    required this.pinController,
    required this.onConfirmContinue,
    required this.onConfirmEndEscort,
    required this.onExtendFiveMinutes,
    this.impactGForce = 1.0,
    this.wrongAttempts = 0,
  });

  final int secondsRemaining;
  final TextEditingController pinController;
  final VoidCallback onConfirmContinue;
  final VoidCallback onConfirmEndEscort;
  final VoidCallback onExtendFiveMinutes;
  final double impactGForce;
  final int wrongAttempts;

  @override
  Widget build(BuildContext context) {
    final isImpact = impactGForce >= 3.5;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD9A441), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                const Expanded(
                  child: Text('Are you OK?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                Text(
                  '$secondsRemaining s',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: MokgosiColors.warning,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isImpact
                  ? 'We felt a hard impact (${impactGForce.toStringAsFixed(1)} g). Enter your PIN, or your trusted contact gets an alert.'
                  : 'Enter your PIN, or your trusted contact gets an alert.',
              style: const TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('checkin_pin_field'),
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
            ),
            if (wrongAttempts > 0) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'That PIN didn’t match. The timer is still running.',
                style: TextStyle(color: MokgosiColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('confirm_pin_button'),
              onPressed: onConfirmContinue,
              child: const Text('I’m OK, keep going'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('end_escort_pin_button'),
              onPressed: onConfirmEndEscort,
              child: const Text('I’ve arrived, end the walk'),
            ),
            TextButton(
              key: const Key('extend_five_minutes_button'),
              onPressed: onExtendFiveMinutes,
              child: const Text('Add 5 minutes'),
            ),
          ],
        ),
      ),
    );
  }
}
