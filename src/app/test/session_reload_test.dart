import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/features/instructor/sessions/create_session_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows the session screen as a fresh page (like a browser reload) on the
/// same data.
Future<void> _open(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CreateSessionScreen(key: UniqueKey()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a reload comes back to the open session', (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await _open(tester, services);
    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();
    final code = (await services.sessions.latestOpenSession(
      ownerId: services.auth.instructorId!,
      courseId: 'database_systems',
    ))!
        .code;

    await _open(tester, services); // "reload"
    // Offered, not opened by itself: "create" is still there.
    expect(find.text('You have a session that is still open'), findsOneWidget);
    expect(find.textContaining(code), findsOneWidget);
    expect(find.text('Create session'), findsOneWidget);

    await tester.tap(find.text('Continue this session'));
    await tester.pumpAndSettle();
    expect(find.text('Create session'), findsNothing);
    expect(find.text('Join code: $code'), findsOneWidget);
    expect(find.text('Close session'), findsOneWidget);
  });

  testWidgets('the open session can be closed from the card', (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await _open(tester, services);
    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();

    await _open(tester, services); // "reload"
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close session'));
    await tester.pumpAndSettle();
    expect(find.text('You have a session that is still open'), findsNothing);
    expect(find.text('Create session'), findsOneWidget);
    expect(
      await services.sessions.latestOpenSession(
        ownerId: services.auth.instructorId!,
        courseId: 'database_systems',
      ),
      isNull,
    );
  });

  testWidgets('after closing: start a new session; a closed one is not '
      'restored', (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await _open(tester, services);
    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close session'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start a new session'));
    await tester.pumpAndSettle();
    expect(find.text('Create session'), findsOneWidget);

    await _open(tester, services); // reload: the closed one stays closed
    expect(find.text('Create session'), findsOneWidget);
  });
}
