import 'package:flutter/material.dart';

/// 15-second haptic check-in card with obscured 4-digit PIN entry,
/// explicit "Continue Escort" vs "End Escort Safely" actions, and +5 minute extension.
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
      color: const Color(0xff321a20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffff7676), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'CHECK IN · $secondsRemaining s',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xffff7676),
              ),
            ),
            if (isImpact) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Physical impact detected (${impactGForce.toStringAsFixed(1)}g)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffffc470),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const Key('checkin_pin_field'),
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Enter PIN',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (wrongAttempts > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'PIN not recognized ($wrongAttempts/3). Timer continues.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffffb3b3), fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('confirm_pin_button'),
              onPressed: onConfirmContinue,
              child: const Text('CONFIRM SAFE / DURESS'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('end_escort_pin_button'),
              onPressed: onConfirmEndEscort,
              child: const Text("I'M HOME SAFE — END ESCORT"),
            ),
            TextButton(
              key: const Key('extend_five_minutes_button'),
              onPressed: onExtendFiveMinutes,
              child: const Text('+5 MINUTES'),
            ),
          ],
        ),
      ),
    );
  }
}

