import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mokgosi_mobile/main.dart';

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

void main() {
  setUp(() async {
    await PlatformStore.clear();
    IncidentApi.simulateOfflineMode = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mokgosi/platform'), (call) async {
      return null;
    });

    IncidentApi.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/evidence-entries/share')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'bundle_id': 'bundle-xyz-123',
            'download_url': '/download/bundle-xyz-123.zip',
            'recipient_type': 'LEGAL',
            'expires_in_hours': 2,
          }),
          200,
        );
      }
      if (path.contains('/evidence-entries')) {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'status': 'SUCCESS',
              'entries': [
                {
                  'id': 'ent-1',
                  'user_id': 'SURVIVOR_001',
                  'kind': 'NOTE',
                  'notes': 'Initial documented incident',
                  'captured_at_utc': '2026-10-23T08:00:00Z',
                  'storage_path': 'local-vault/note_1.txt',
                  'manifest_id': 'man-1',
                  'is_synced': true,
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'status': 'CREATED',
              'entry': {
                'id': 'ent-2',
                'user_id': 'SURVIVOR_001',
                'kind': 'NOTE',
                'notes': 'Second note',
                'captured_at_utc': '2026-10-23T08:30:00Z',
                'manifest_id': 'man-2',
                'is_synced': true,
              },
            }),
            201,
          );
        }
        if (request.method == 'DELETE') {
          return http.Response(jsonEncode({'status': 'DELETED'}), 200);
        }
      }
      return http.Response('{"status":"OK"}', 200);
    });
  });

  group('Phase G4 Evidence Mode Widget Tests', () {
    testWidgets('EvidenceScreen displays initial entries with sync status and capture buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001', allowSampleCaptures: true)),
      );
      await pumpUntilNoLoader(tester);

      // Verify UI header & capture buttons
      expect(find.text('Journal'), findsOneWidget);
      expect(find.byKey(const Key('btn_record_audio')), findsOneWidget);
      expect(find.byKey(const Key('btn_take_photo')), findsOneWidget);
      expect(find.byKey(const Key('btn_write_note')), findsOneWidget);

      // Verify existing entry loaded from API
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Initial documented incident'), findsOneWidget);
      expect(find.text('Backed up and signed'), findsOneWidget);
    });

    testWidgets('Capturing a note silently saves and updates timeline in offline mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001')),
      );
      await pumpUntilNoLoader(tester);

      // Tap write note
      await tester.tap(find.byKey(const Key('btn_write_note')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.widgetWithText(AlertDialog, 'Write a note'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('note_input_field')), 'Verbal threats witnessed by neighbour.');
      await tester.tap(find.byKey(const Key('save_note_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await pumpUntilNoLoader(tester);

      // Verify entry is displayed with "Saved on this phone" indicator
      expect(find.widgetWithText(ListTile, 'Verbal threats witnessed by neighbour.'), findsOneWidget);
      expect(find.text('Only on this phone'), findsOneWidget);
    });

    testWidgets('Sample captures stay hidden outside demo builds', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      IncidentApi.simulateOfflineMode = true;
      await tester.pumpWidget(const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001')));
      await pumpUntilNoLoader(tester);
      // Recording and photos are not built yet; a real build must not pretend to capture them.
      expect(find.byKey(const Key('btn_record_audio')), findsNothing);
      expect(find.byKey(const Key('btn_take_photo')), findsNothing);
      expect(find.byKey(const Key('btn_write_note')), findsOneWidget);
    });

    testWidgets('Demo sample audio and photo entries are labelled as placeholders', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001', allowSampleCaptures: true)),
      );
      await pumpUntilNoLoader(tester);

      // Trigger silent audio capture
      await tester.tap(find.byKey(const Key('btn_record_audio')));
      await pumpUntilNoLoader(tester);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.textContaining('Sample recording (demo'), findsOneWidget);

      // Trigger silent photo capture
      await tester.tap(find.byKey(const Key('btn_take_photo')));
      await pumpUntilNoLoader(tester);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.textContaining('Sample photo (demo'), findsOneWidget);
    });

    testWidgets('Multi-selection creates case bundle and shows download modal + audit log', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001')),
      );
      await pumpUntilNoLoader(tester);

      // Select the entry via Checkbox
      final checkboxFinder = find.byType(Checkbox).first;
      await tester.tap(checkboxFinder);
      await tester.pump();

      // Multi-select bar appears
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const Key('share_selected_button')), findsOneWidget);

      // Open share dialog
      await tester.tap(find.byKey(const Key('share_selected_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Share 1 entry'), findsOneWidget);
      expect(find.byKey(const Key('generate_bundle_button')), findsOneWidget);

      // Generate bundle
      await tester.tap(find.byKey(const Key('generate_bundle_button')));
      await pumpUntilNoLoader(tester);

      // Modal appears with expiring link explanation
      expect(find.text('Link ready'), findsOneWidget);
      expect(find.textContaining('stops working after 2 hours'), findsOneWidget);
      // The link points at the configured API, not an invented host.
      expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.data == '${MokgosiConfig.apiBase}/download/bundle-xyz-123.zip'),
        findsOneWidget,
      );

      // Close modal
      await tester.tap(find.text('Done'));
      await tester.pump();

      // History audit log visible
      expect(find.text('Shared'), findsOneWidget);
      expect(find.textContaining('Shared 1 entry with lawyer or legal aid'), findsOneWidget);
    });

    testWidgets('Entry deletion removes item from timeline and local vault', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      IncidentApi.simulateOfflineMode = true;

      // Seed one entry in offline cache
      await IncidentApi.storeEvidenceEntry(
        userId: 'SURVIVOR_001',
        kind: 'NOTE',
        notes: 'Temporary test entry to be deleted',
      );

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001')),
      );
      await pumpUntilNoLoader(tester);

      expect(find.text('Temporary test entry to be deleted'), findsOneWidget);

      // Tap delete icon
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Delete this entry?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_delete_entry')));
      await pumpUntilNoLoader(tester);

      // Deleted entry should no longer appear
      expect(find.text('Temporary test entry to be deleted'), findsNothing);
    });

    testWidgets('Quick exit resets navigation to CalculatorDisguiseScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: EvidenceScreen(userId: 'SURVIVOR_001')),
      );
      await pumpUntilNoLoader(tester);

      await tester.tap(find.byKey(const Key('evidence_quick_exit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CalculatorDisguiseScreen), findsOneWidget);
    });
  });
}
