import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'participant'; // InMemoryAuthService's student

const _feedback = StudentFeedback(
  language: Language.en,
  concepts: [
    FeedbackConcept(
      conceptId: 'primary_key',
      name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
      state: MasteryState.emerging,
      attempts: 2,
      correct: 1,
    ),
  ],
);

Future<(AppServices, Session)> _setUp() async {
  final services = AppServices.inMemory(initialLocale: const Locale('en'));
  final session = await services.sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: const [],
  );
  await services.sessions.closeSession(session.id);
  await services.sessions.saveFeedback(session.id, {_me: _feedback});
  await services.sessions.releaseFeedback(session.id);
  return (services, session);
}

/// Lets the in-memory repositories' real async work finish (pumpAndSettle
/// alone does not, while a spinner runs).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _show(WidgetTester tester, AppServices services, Session s) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(
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
      home: FeedbackScreen(sessionId: s.id, participantId: _me),
    ),
  ));
  await _settle(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('declining stores nothing; agreeing saves the session',
      (tester) async {
    final (services, session) = await _setUp();
    await _show(tester, services, session);
    expect(find.text('Keep your progress (optional)'), findsOneWidget);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsOneWidget);
    expect(find.textContaining('Who sees it: only you'), findsOneWidget);
    await tester.tap(find.text('No, thanks'));
    await tester.pumpAndSettle();
    expect(services.auth.studentAccount, isNull);
    expect(await services.profiles.consentVersion(_me), isNull);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('This session is in your profile.'), findsOneWidget);
    expect(services.auth.studentAccount, isNotNull);
    expect(await services.profiles.hasSession(_me, session.id), isTrue);
  });

  testWidgets('my profile: progress, remove a session, delete everything',
      (tester) async {
    final (services, session) = await _setUp();
    await services.auth.linkStudentAccount();
    await services.profiles.create(_me);
    await services.profiles.saveSession(_me, session, _feedback);
    await _show(tester, services, session);
    expect(find.text('This session is in your profile.'), findsOneWidget);

    await tester.tap(find.text('Open my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Primary Key'), findsOneWidget);
    expect(find.textContaining('Still forming'), findsOneWidget);
    expect(find.textContaining('1 of 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(await services.profiles.hasSession(_me, session.id), isFalse);
    expect(find.text('No sessions added yet.'), findsWidgets);

    await tester.tap(find.text('Delete my whole profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('without your name'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(await services.profiles.consentVersion(_me), isNull);
    expect(find.text('Your profile was deleted.'), findsOneWidget);
  });
}
