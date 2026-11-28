import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openProfile(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(BouslaApp(services: services));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(Scaffold).first)).pushNamed('/me');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guest cannot see the signed-in dashboard', (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await openProfile(tester, services);
    expect(find.byKey(const ValueKey('dashboard-join')), findsNothing);
    expect(services.auth.studentAccount, isNull);
  });

  testWidgets('linked student sees the dashboard even with no saved sessions',
      (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    final account = await services.auth.linkStudentAccount();
    await services.profiles.create(account.uid);
    await openProfile(tester, services);
    expect(find.byKey(const ValueKey('dashboard-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-career')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('dashboard-map')));
    await tester.tap(find.byKey(const ValueKey('dashboard-map')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Join a session and save your feedback'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic dashboard fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory(initialLocale: const Locale('ar'));
    final account = await services.auth.linkStudentAccount();
    await services.profiles.create(account.uid);
    await openProfile(tester, services);
    expect(find.text('أين وصلت في رحلتك التعليمية؟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
