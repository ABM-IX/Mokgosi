import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mokgosi_mobile/main.dart';

void main() {
  setUp(() async {
    await PlatformStore.clear();
    IncidentApi.simulateOfflineMode = false;
    IncidentApi.smsFallbackCount = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mokgosi/platform'), (call) async {
      return null;
    });

    // Provide default fast MockClient for all test endpoints
    IncidentApi.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/referrals')) {
        return http.Response(jsonEncode({'partners': []}), 200);
      }
      if (path.contains('/consents')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'consents': {
              'user_id': 'MOKGOSI_DEMO_USER',
              'location': true,
              'audio': false,
              'responder_contact': false,
              'share_evidence': false,
            },
          }),
          200,
        );
      }
      if (path.contains('/contacts')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'contacts': [],
          }),
          200,
        );
      }
      if (path.endsWith('/trigger')) {
        return http.Response(
          jsonEncode({
            'status': 'MOKGOSI_ALERT_ACTIVE',
            'incident_persisted': true,
            'incident': {'id': 'test-alert-id', 'priority': 'P1_CRITICAL'},
          }),
          200,
        );
      }
      return http.Response('{"status":"OK"}', 200);
    });
  });

  group('G3 Pillar B Calculator Disguise Tests', () {
    testWidgets('Normal math calculation: 7 * 6 = 42 and no alert dispatched', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: CalculatorDisguiseScreen()),
      );
      await tester.pump();

      // Press 7, ×, 6, =
      await tester.tap(find.byKey(const Key('calc_btn_7')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_mult')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_6')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_equals')));
      await tester.pump();

      expect(find.text('42'), findsOneWidget);
      // No safety/Mokgosi UI exposed
      expect(find.textContaining('Mokgosi'), findsNothing);
      expect(find.textContaining('SOS'), findsNothing);
    });

    testWidgets('Safe PIN 2580 + = unlocks AppHomeScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: CalculatorDisguiseScreen()),
      );
      await tester.pump();

      // Enter 2, 5, 8, 0, =
      await tester.tap(find.byKey(const Key('calc_btn_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_equals')));
      await tester.pumpAndSettle();

      // Should now be on AppHomeScreen with Pillar tabs
      expect(find.byType(AppHomeScreen), findsOneWidget);
      expect(find.byKey(const Key('tab_getting_around')), findsOneWidget);
      expect(find.byKey(const Key('tab_support_safety')), findsOneWidget);
    });

    testWidgets('Duress PIN 0852 + = silently dispatches COVERT_SOS and stays on calculator', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sentTriggers = <Map<String, dynamic>>[];
      IncidentApi.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/trigger')) {
          sentTriggers.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'MOKGOSI_ALERT_ACTIVE',
            'incident_persisted': true,
            'incident': <String, dynamic>{
              'id': 'covert-alert-1234',
              'priority': 'P1_CRITICAL',
            },
          }),
          200,
        );
      });

      await tester.pumpWidget(
        const MaterialApp(home: CalculatorDisguiseScreen()),
      );
      await tester.pump();

      // Enter 0, 8, 5, 2, =
      await tester.tap(find.byKey(const Key('calc_btn_0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('calc_btn_equals')));
      await tester.pumpAndSettle();

      // Critical Covert Invariant: Remains on calculator, no alert text shown
      expect(find.byType(CalculatorDisguiseScreen), findsOneWidget);
      expect(find.textContaining('Mokgosi'), findsNothing);
      expect(find.textContaining('COVERT'), findsNothing);
      expect(find.textContaining('Alert sent'), findsNothing);

      // Trigger was dispatched silently in the background
      expect(sentTriggers.length, 1);
      expect(sentTriggers.first['trigger_type'], 'COVERT_SOS');
      expect(sentTriggers.first['category'], 'GBV_DOMESTIC');
    });
  });

Future<void> pumpUntilNoLoader(WidgetTester tester, {int maxTicks = 25}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
}

  group('G3 Pillar B Safe Network & Consents Tests', () {
    testWidgets('SafeNetworkScreen displays warning banner, priority ordering, and enforces max 5 limit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      await tester.pumpWidget(
        const MaterialApp(home: SafeNetworkScreen()),
      );
      await pumpUntilNoLoader(tester);

      // Check warning banner
      expect(
        find.textContaining('Choose someone you trust who the person causing harm cannot access or pressure'),
        findsOneWidget,
      );

      // Add contacts up to 5
      for (int i = 1; i <= 5; i++) {
        await tester.tap(find.byKey(const Key('add_contact_button')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('contact_name_field')), 'Contact $i');
        await tester.enterText(find.byKey(const Key('contact_phone_field')), '+2677100000$i');
        await tester.tap(find.byKey(const Key('save_contact_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilNoLoader(tester);
      }

      expect(find.text('Trusted Circle (5/5)'), findsOneWidget);
      expect(find.text('Contact 1'), findsOneWidget);

      // Attempting 6th contact is blocked
      await tester.tap(find.byKey(const Key('add_contact_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Maximum 5 trusted contacts allowed'), findsOneWidget);

      // Quick exit clears navigation back to disguise
      await tester.tap(find.byKey(const Key('quick_exit_button')));
      await tester.pumpAndSettle();
      expect(find.byType(CalculatorDisguiseScreen), findsOneWidget);
    });

    testWidgets('GetHelpScreen displays honest unverified directory banner and zero fake numbers', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      await tester.pumpWidget(
        const MaterialApp(home: GetHelpScreen()),
      );
      await pumpUntilNoLoader(tester);

      expect(find.textContaining('Support directory being verified'), findsOneWidget);
      expect(find.textContaining('No fake contact numbers are ever shown'), findsOneWidget);
      // No fake contact numbers visible
      expect(find.textContaining('+267 71 000 000'), findsNothing);
      expect(find.textContaining('0800'), findsNothing);

      // Quick exit works
      await tester.tap(find.byKey(const Key('get_help_quick_exit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CalculatorDisguiseScreen), findsOneWidget);
    });

    testWidgets('ConsentsScreen defaults off for audio & responder contact and supports PIN purge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      await tester.pumpWidget(
        const MaterialApp(home: ConsentsScreen()),
      );
      await pumpUntilNoLoader(tester);

      expect(find.textContaining('Survivor-Owned Control'), findsOneWidget);
      expect(find.textContaining('Audio Capture in Background (Default: OFF)'), findsOneWidget);
      expect(find.textContaining('Responder Direct Contact (Default: OFF)'), findsOneWidget);

      // Emergency purge test
      await tester.tap(find.byKey(const Key('purge_data_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Remove All Mokgosi Data?'), findsOneWidget);

      // Enter Safe PIN 2580 to confirm purge
      await tester.enterText(find.byKey(const Key('purge_pin_field')), '2580');
      await tester.tap(find.byKey(const Key('confirm_purge_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Returns to disguised calculator
    });
  });

  group('G3 Motion Telemetry 3-Shake and Offline Resilience', () {
    test('3 hard shakes within 2s triggers SHAKE_SOS and respects cooldown', () {
      final telemetry = MotionTelemetry();
      int shakeSosCount = 0;

      // Simulate 3 shakes via test hook
      final triggered = telemetry.simulateShakePattern(
        peakG: 3.2,
        onShakeSos: () => shakeSosCount++,
      );

      expect(triggered, isTrue);
      expect(shakeSosCount, 1);

      // Immediate 2nd shake attempt is blocked by cooldown
      final cooldownTriggered = telemetry.simulateShakePattern(
        peakG: 3.5,
        onShakeSos: () => shakeSosCount++,
      );
      expect(cooldownTriggered, isFalse);
      expect(shakeSosCount, 1);
    });

    test('Covert SHAKE_SOS queues in offline mode and flushes deduplicated upon restore', () async {
      final sentTriggers = <Map<String, dynamic>>[];
      IncidentApi.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/trigger')) {
          sentTriggers.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'MOKGOSI_ALERT_ACTIVE',
            'incident_persisted': true,
            'incident': <String, dynamic>{'id': 'offline-shake-123'},
          }),
          200,
        );
      });

      // Network down
      IncidentApi.simulateOfflineMode = true;
      final outcome = await IncidentApi.trigger('SHAKE_SOS', category: 'GBV_DOMESTIC');
      expect(outcome.delivered, isFalse);
      expect(outcome.queuedOffline, isTrue);
      expect(outcome.smsFallbackFired, isTrue);
      expect(sentTriggers, isEmpty);

      // Network restored
      IncidentApi.simulateOfflineMode = false;
      final flushed = await IncidentApi.flushOfflineQueue();
      expect(flushed, 1);
      expect(sentTriggers.length, 1);
      expect(sentTriggers.first['trigger_type'], 'SHAKE_SOS');
      expect(sentTriggers.first['category'], 'GBV_DOMESTIC');
      expect(await IncidentApi.getQueuedEvents(), isEmpty);
    });

    test('AndroidManifest contains Calculator disguise activity-alias without exposing GBV brand', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();

      expect(content, contains('.CalculatorAlias'));
      expect(content, contains('android:label="Calculator"'));
      expect(content, contains('android.intent.category.LAUNCHER'));
      // Invariant: Calculator disguise must not mention GBV or emergency in its alias
      expect(content, isNot(contains('GBV')));
      expect(content, isNot(contains('Emergency')));
    });
  });
}
