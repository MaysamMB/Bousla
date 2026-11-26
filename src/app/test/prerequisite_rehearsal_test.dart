import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/sessions/live_insights_panel.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Offline regression: the built-in sample contains two PK and two FK questions.
// Synthetic responses never leave the in-memory repositories.
Future<(AppServices, Session)> fixture(int gaps) async {
  final services = AppServices.inMemory(initialLocale: const Locale('en'));
  final questions = (await services.content.listQuestions('database_systems'))
      .where((q) => q.id.startsWith('db_pk_') || q.id.startsWith('db_fk_'))
      .toList();
  expect(questions.length, 4);
  final keys = await services.content.answerKeys('database_systems');
  final session = await services.sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  for (var s = 0; s < 3; s++) {
    final id = await services.sessions.join(session.id);
    for (final q in questions) {
      final key = keys.firstWhere(
        (k) => k.questionId == q.id && k.questionVersion == q.version,
      );
      // All three struggle with FK; only [gaps] also struggle with PK.
      final wrong = q.id.startsWith('db_fk_') || s < gaps;
      await services.sessions.submitResponse(
        session.id,
        Response(
          participantId: id,
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId: wrong
              ? q.options.firstWhere((o) => o.id != key.correctOptionId).id
              : key.correctOptionId,
          displayLanguage: s.isEven ? Language.ar : Language.en,
        ),
      );
    }
  }
  return (services, session);
}

Future<void> showPanel(
    WidgetTester tester, AppServices services, Session session,
    {String locale = 'en'}) async {
  tester.view.physicalSize = const Size(1280, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(
    services: services,
    child: MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(child: LiveInsightsPanel(session: session)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('three shared gaps: a real, cautious FK/PK signal',
      (tester) async {
    final (services, session) = await fixture(3);
    await showPanel(tester, services, session);
    expect(find.text('Prerequisites worth reviewing'), findsOneWidget);
    expect(
        find.text('3 of the 3 students with a possible difficulty in '
            'Foreign Key also show one in Primary Key.'),
        findsOneWidget);
    expect(
        find.text('Primary Key may be a contributing cause: consider '
            'reviewing it with the class.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two shared gaps: signal hidden despite three respondents',
      (tester) async {
    final (services, session) = await fixture(2);
    await showPanel(tester, services, session);
    expect(find.textContaining('3 answered ·'), findsWidgets);
    expect(find.text('Prerequisites worth reviewing'), findsNothing);
    expect(find.textContaining('may be a contributing cause'), findsNothing);
  });

  testWidgets('Arabic cautious signal and presentation mode', (tester) async {
    final (services, session) = await fixture(3);
    await showPanel(tester, services, session, locale: 'ar');
    final title = find.text('متطلبات سابقة تستحق المراجعة');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
    expect(
        find.text(
            'قد يكون المفتاح الأساسي سبباً محتملاً، ويُقترح مراجعته مع الصف.'),
        findsOneWidget);
    // The current design hides detailed signals in presentation mode.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
  });
}
