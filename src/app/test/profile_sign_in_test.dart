// "My profile" with no profile in this browser: sign in with Google.
import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openProfile(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BouslaApp(services: services));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(Scaffold).first)).pushNamed('/me');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no profile: sign in, agree, and the profile opens',
      (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await _openProfile(tester, services);
    expect(find.text('Sign in with Google'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsOneWidget);
    await tester.tap(find.text('I agree, create my profile'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-sign-in')), findsNothing);
    final uid = services.auth.studentAccount!.uid;
    expect(await services.profiles.consentVersion(uid), 1);
  });

  testWidgets('a profile from another browser opens without asking again',
      (tester) async {
    final auth = InMemoryAuthService()..existingStudentUid = 'elsewhere';
    final services = AppServices(
      content: InMemoryContentRepository(),
      sessions: InMemorySessionRepository(),
      auth: auth,
      inMemory: true,
      initialLocale: const Locale('en'),
    );
    await services.profiles.create('elsewhere');
    await _openProfile(tester, services);

    await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsNothing);
    expect(find.byKey(const ValueKey('profile-header')), findsOneWidget);
    expect(services.auth.studentAccount!.uid, 'elsewhere');
  });

  testWidgets('declining consent stores nothing', (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('ar'));
    await _openProfile(tester, services);
    expect(find.text('تسجيل الدخول بحساب Google'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-sign-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لا، شكراً'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يُحفظ شيء'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-header')), findsNothing);
    expect(await services.profiles.consentVersion('participant'), isNull);
  });
}
