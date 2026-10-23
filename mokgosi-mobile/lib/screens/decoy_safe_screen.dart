import 'package:flutter/material.dart';

/// Covert screen displayed after Duress PIN (`0852`) or 3 consecutive wrong PINs.
/// Entered via `pushAndRemoveUntil` and wrapped in `PopScope(canPop: false)` so
/// back-navigation is blocked and nothing on screen reveals an active alert.
class DecoySafeScreen extends StatelessWidget {
  const DecoySafeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Color(0xfff4f6f7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.check_circle,
                    color: Color(0xff3a9d75),
                    size: 72,
                    semanticLabel: 'Journey completed icon',
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Journey Completed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff20332b),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Location sharing turned off',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff63736c),
                      fontSize: 15,
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
}

