import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mokgosi_mobile/main.dart';

void main() {
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mokgosi/platform'), (call) async {
      return null;
    });
    await PlatformStore.clear();
  });

  void configurePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('LoginScreen renders brand, tabs, inputs, and emergency guest bypass', (tester) async {
    configurePhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    expect(find.text('MOKGOSI'), findsOneWidget);
    expect(find.text('Your call for help. A connected response.'), findsOneWidget);
    expect(find.byKey(const Key('tab_sign_in')), findsOneWidget);
    expect(find.byKey(const Key('btn_sign_in_submit')), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('btn_guest_access')), findsOneWidget);
    expect(find.text('Quick Emergency Access (No Account)'), findsOneWidget);
  });

  testWidgets('LoginScreen demo auto-fill populates verified citizen credentials', (tester) async {
    configurePhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.text('Demo Auto-fill'));
    await tester.pump();

    final emailFinder = find.byKey(const Key('login_email_field'));
    final TextField emailField = tester.widget(emailFinder);
    expect(emailField.controller?.text, 'citizen@mokgosi.org');
  });

  testWidgets('LoginScreen displays validation error when submitting empty fields', (tester) async {
    configurePhoneViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.byKey(const Key('btn_sign_in_submit')));
    await tester.pump();

    expect(find.text('Please enter your email, phone, or citizen ID.'), findsOneWidget);
  });

  testWidgets('LoginScreen sign-in persists auth_user_id to PlatformStore and triggers onAuthenticated', (tester) async {
    configurePhoneViewport(tester);
    bool authenticated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onAuthenticated: () => authenticated = true,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_email_field')), 'kabo@mokgosi.org');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_sign_in_submit')));
    await tester.pump();

    expect(authenticated, isTrue);
    final storedUser = await PlatformStore.read('auth_user_id');
    final storedRole = await PlatformStore.read('auth_role');
    expect(storedUser, 'kabo@mokgosi.org');
    expect(storedRole, 'CITIZEN');
  });

  testWidgets('LoginScreen Emergency Guest Access sets private GUEST session without account', (tester) async {
    configurePhoneViewport(tester);
    bool authenticated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onAuthenticated: () => authenticated = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('btn_guest_access')));
    await tester.pump();

    expect(authenticated, isTrue);
    final storedUser = await PlatformStore.read('auth_user_id');
    final storedRole = await PlatformStore.read('auth_role');
    expect(storedUser, startsWith('GUEST_'));
    expect(storedRole, 'GUEST');
  });

  testWidgets('AuthGate routes to LoginScreen when unauthenticated and AppHomeScreen when session exists', (tester) async {
    configurePhoneViewport(tester);
    await PlatformStore.clear();

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(key: Key('auth_logged_out')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Logged out: should show LoginScreen
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('tab_sign_in')), findsOneWidget);

    // Now simulate an active session
    await PlatformStore.write('auth_user_id', 'lorato@mokgosi.org');

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(key: Key('auth_logged_in')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Logged in: should show AppHomeScreen
    expect(find.byType(AppHomeScreen), findsOneWidget);
  });
}
