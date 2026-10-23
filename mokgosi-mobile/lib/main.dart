import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/mokgosi_config.dart';
import 'services/incident_api.dart';

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

class EscortHome extends StatefulWidget {
  const EscortHome({super.key});

  @override
  State<EscortHome> createState() => _EscortHomeState();
}

class _EscortHomeState extends State<EscortHome> {
  Timer? _timer;
  int _seconds = 0;
  bool _active = false;
  bool _checking = false;
  final _pin = TextEditingController();
  String _message = 'Your call for help. A connected response.';

  @override
  void dispose() {
    _timer?.cancel();
    _pin.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _active = true);
    _count(MokgosiConfig.demoEscortSeconds, _showCheckin);
  }

  void _count(int seconds, VoidCallback done) {
    _timer?.cancel();
    setState(() => _seconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) {
        timer.cancel();
        done();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _showCheckin() {
    if (!mounted) return;
    HapticFeedback.vibrate();
    setState(() => _checking = true);
    _count(MokgosiConfig.checkinSeconds, () => _send('MISSED_CHECKIN'));
  }

  Future<void> _send(String trigger) async {
    _timer?.cancel();
    try {
      final result = await IncidentApi.trigger(trigger);
      final persisted = result['incident_persisted'] == true;
      final contactQueued = result['notification_state'] == 'QUEUED' ||
          result['notification_state'] == 'ALREADY_QUEUED';
      final deliveryLabel = result['notification_mode'] == 'DEMO_ONLY'
          ? 'DEMO: trusted-person message only logged'
          : contactQueued
              ? 'Trusted-person notification queued'
              : 'Trusted-person contact not configured';
      if (mounted) {
        setState(() => _message = persisted
            ? 'Incident recorded. $deliveryLabel.'
            : 'Incident not recorded (${result['persistence_state']}). $deliveryLabel.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Alert could not be delivered. Please retry.');
    }
  }

  void _submitPin() {
    final value = _pin.text.trim();
    _pin.clear();
    if (value == MokgosiConfig.safePin) {
      _timer?.cancel();
      setState(() => _checking = false);
      _start();
    } else if (value == MokgosiConfig.duressPin) {
      setState(() => _checking = false);
      _send('DURESS_PIN');
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DecoySafeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN not recognized')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MOKGOSI'),
            Text(
              'PERSONAL SAFETY & RESPONSE NETWORK',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SizedBox(height: 18),
            const Icon(Icons.shield_outlined, size: 76, color: Color(0xff55d9ad)),
            const SizedBox(height: 18),
            Text(
              _active ? 'ESCORT ACTIVE' : 'YOU ARE IN CONTROL',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21),
            ),
            const SizedBox(height: 12),
            Text(
              _active ? 'Check-in in $_seconds seconds' : _message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 26),
            if (_active)
              LinearProgressIndicator(
                value: 1 - (_seconds / MokgosiConfig.demoEscortSeconds),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            const SizedBox(height: 24),
            if (!_active && !_checking)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.directions_walk),
                label: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('START 30 SECOND ESCORT'),
                ),
              ),
            if (_active && !_checking)
              OutlinedButton(
                onPressed: _showCheckin,
                child: const Text('CHECK IN NOW'),
              ),
            if (_checking) _buildCheckinCard(),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _send('EXPLICIT_SOS'),
              icon: const Icon(Icons.sos, color: Colors.redAccent),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('SEND SOS'),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Trusted person  ·  +267 71 000 000',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demo PINs: safe 2580 · duress 0852',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckinCard() {
    return Card(
      color: const Color(0xff321a20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(
              'CHECK IN · $_seconds s',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xffff7676),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Enter PIN', counterText: ''),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitPin,
              child: const Text('CONFIRM SAFE / DURESS'),
            ),
            TextButton(
              onPressed: () => _count(_seconds + 300, _showCheckin),
              child: const Text('+5 MINUTES'),
            ),
          ],
        ),
      ),
    );
  }
}

class DecoySafeScreen extends StatelessWidget {
  const DecoySafeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xfff4f6f7),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Color(0xff3a9d75), size: 72),
            SizedBox(height: 16),
            Text(
              'Journey Completed',
              style: TextStyle(
                color: Color(0xff20332b),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('Location sharing turned off', style: TextStyle(color: Color(0xff63736c))),
          ],
        ),
      ),
    );
  }
}
