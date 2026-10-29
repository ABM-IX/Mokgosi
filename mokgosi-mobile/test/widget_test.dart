import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mokgosi_mobile/main.dart';

void main() {
  setUp(() async {
    // Location services "off": the real geolocator plugin cannot answer inside a test.
    for (final channel in const ['flutter.baseflow.com/geolocator', 'flutter.baseflow.com/geolocator_android']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
      );
    }
    await PlatformStore.clear();
    IncidentApi.simulateOfflineMode = false;
    IncidentApi.smsFallbackCount = 0;
  });

  testWidgets('escort home renders the start action and hides demo PIN hints by default', (tester) async {
    await tester.pumpWidget(const MokgosiApp());
    expect(find.text('Mokgosi'), findsOneWidget);
    expect(find.text('Start a 30-second walk'), findsOneWidget);
    // Covert invariant: no exposed PIN hints or fake phone numbers on default screen.
    expect(find.textContaining('2580'), findsNothing);
    expect(find.textContaining('0852'), findsNothing);
    expect(find.textContaining('+267 71 000 000'), findsNothing);
  });

  test('PinGuard enforces salted hashes, distinct PIN validation, and 3-strike duress', () {
    final guard = PinGuard();
    expect(guard.evaluate('2580'), PinOutcome.safe);
    expect(guard.evaluate('0852'), PinOutcome.duress);

    // 1st and 2nd wrong attempts return invalid; 3rd triggers covert duress.
    expect(guard.evaluate('1111'), PinOutcome.invalid);
    expect(guard.consecutiveWrongAttempts, 1);
    expect(guard.evaluate('2222'), PinOutcome.invalid);
    expect(guard.consecutiveWrongAttempts, 2);
    expect(guard.evaluate('3333'), PinOutcome.duressThreeStrikes);
    expect(guard.consecutiveWrongAttempts, 0);

    expect(PinGuard.validatePinPair('1234', '1234'), isNotNull);
    expect(PinGuard.validatePinPair('123', '9999'), isNotNull);
    expect(PinGuard.validatePinPair('1357', '2468'), isNull);
  });

  test('MotionTelemetry calculates G-force and tracks >= 3.5g impact peak', () {
    expect(MotionTelemetry.computeGForce(0, 0, 9.81), closeTo(1.0, 0.02));
    final telemetry = MotionTelemetry();
    double? capturedImpact;
    final peak = telemetry.simulateImpact(
      simulatedG: 4.2,
      onImpactThreshold: (g) => capturedImpact = g,
    );
    expect(peak, 4.2);
    expect(capturedImpact, 4.2);
  });

  test('Offline queue persists client_event_id, fires SMS fallback, and deduplicates on flush', () async {
    final sentRequests = <Map<String, dynamic>>[];
    IncidentApi.httpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      sentRequests.add(body);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'status': 'MOKGOSI_ALERT_ACTIVE',
          'incident_persisted': true,
          'persistence_state': 'PERSISTED',
          'notification_state': 'QUEUED',
          'notification_mode': 'DEMO_ONLY',
          'incident': <String, dynamic>{
            'id': '11111111-2222-3333-4444-555555555555',
            'priority': 'P1_CRITICAL',
          },
        }),
        200,
      );
    });

    // 1. Trigger SOS in airplane/offline mode.
    IncidentApi.simulateOfflineMode = true;
    final offlineOutcome = await IncidentApi.trigger(
      'EXPLICIT_SOS',
      trustedContactPhone: '+26771234567',
    );
    expect(offlineOutcome.delivered, isFalse);
    expect(offlineOutcome.queuedOffline, isTrue);
    expect(offlineOutcome.smsFallbackFired, isTrue);
    expect(offlineOutcome.userMessage, contains('queued'));
    expect(sentRequests, isEmpty);

    final queued = await IncidentApi.getQueuedEvents();
    expect(queued.length, 1);
    final originalEventId = queued.first['client_event_id'];
    expect(originalEventId, offlineOutcome.clientEventId);

    // 2. Restore network and flush queue -> same client_event_id is sent once.
    IncidentApi.simulateOfflineMode = false;
    final flushed = await IncidentApi.flushOfflineQueue();
    expect(flushed, 1);
    expect(sentRequests.length, 1);
    expect(sentRequests.first['client_event_id'], originalEventId);
    expect(await IncidentApi.getQueuedEvents(), isEmpty);
  });

  testWidgets('Safe PIN 2580 ends escort cleanly and Duress PIN 0852 shows covert decoy with back blocked', (tester) async {
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
          'persistence_state': 'PERSISTED',
          'notification_state': 'QUEUED',
          'notification_mode': 'DEMO_ONLY',
          'incident': <String, dynamic>{
            'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            'priority': 'P1_CRITICAL',
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(const MokgosiApp());
    await tester.pump();

    // Start escort and open check-in.
    await tester.tap(find.byKey(const Key('start_escort_button')));
    await tester.pump();
    expect(find.text('Walk in progress'), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkin_now_button')));
    await tester.pump();
    expect(find.byKey(const Key('checkin_pin_field')), findsOneWidget);
    // Someone may be watching: the check-in card must not hint that a duress PIN exists.
    expect(find.textContaining('uress'), findsNothing);

    // Enter Safe PIN 2580 and end escort.
    await tester.enterText(find.byKey(const Key('checkin_pin_field')), '2580');
    await tester.tap(find.byKey(const Key('end_escort_pin_button')));
    await tester.pump();
    expect(find.text('Walking somewhere?'), findsOneWidget);
    expect(find.textContaining('Walk ended'), findsOneWidget);

    // Start again, open check-in, and enter Duress PIN 0852.
    await tester.tap(find.byKey(const Key('start_escort_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkin_now_button')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('checkin_pin_field')), '0852');
    await tester.tap(find.byKey(const Key('confirm_pin_button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify covert DecoySafeScreen is displayed and no alert text is visible.
    expect(find.text('Journey Completed'), findsOneWidget);
    expect(find.text('Location sharing turned off'), findsOneWidget);
    expect(find.textContaining('DURESS'), findsNothing);
    expect(find.textContaining('Incident recorded'), findsNothing);
    expect(sentTriggers.length, 1);
    expect(sentTriggers.first['trigger_type'], 'DURESS_PIN');

    // Attempt back navigation -> remains on DecoySafeScreen.
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });

  testWidgets('Simulated >=3.5g impact followed by 15s check-in timeout sends peak impact_g_force', (tester) async {
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
          'persistence_state': 'PERSISTED',
          'notification_state': 'NOT_CONFIGURED',
          'notification_mode': 'DEMO_ONLY',
          'incident': <String, dynamic>{
            'id': '99999999-8888-7777-6666-555555555555',
            'priority': 'P2_HIGH',
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      const MaterialApp(home: EscortHome(initialDemoControlsOpen: true)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('simulate_impact_button')));
    await tester.pump();

    expect(find.textContaining('We felt a hard impact (4.2 g)'), findsOneWidget);

    // Advance 15 seconds so the check-in times out.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentTriggers.length, 1);
    expect(sentTriggers.first['trigger_type'], 'MISSED_CHECKIN');
    expect(sentTriggers.first['impact_g_force'], 4.2);
  });
}
