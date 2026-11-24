import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/sessions/live_insights_panel.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session of the sample course where [students] students answer every
/// question with a wrong option.
Future<(AppServices, Session)> _session(int students) async {
  final services = AppServices.inMemory(initialLocale: const Locale('en'));
  final questions = await services.content.listQuestions('database_systems');
  final keys = await services.content.answerKeys('database_systems');
  final session = await services.sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  for (var s = 0; s < students; s++) {
    final id = await services.sessions.join(session.id);
    for (final q in questions) {
      final key = keys.firstWhere(
        (k) => k.questionId == q.id && k.questionVersion == q.version,
      );
      await services.sessions.submitResponse(
        session.id,
        Response(
          participantId: id,
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId:
              q.options.firstWhere((o) => o.id != key.correctOptionId).id,
          displayLanguage: s.isEven ? Language.ar : Language.en,
        ),
      );
    }
  }
  return (services, session);
}

Future<void> _show(WidgetTester tester, AppServices services, Session s) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        home: Scaffold(
          body: SingleChildScrollView(child: LiveInsightsPanel(session: s)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('5 students: concept cards with evidence, no hidden ones', (
    tester,
  ) async {
    final (services, session) = await _session(5);
    await _show(tester, services, session);
    expect(find.text('What the class understands'), findsOneWidget);
    expect(find.textContaining('5 answered · 0% correct'), findsWidgets);
    expect(find.textContaining('hidden to protect privacy'), findsNothing);
    expect(find.textContaining('not definitive diagnoses'), findsOneWidget);
    // Each prerequisite signal is two lines: the numbers, then a cautious
    // suggestion.
    final signals = find.textContaining(RegExp('also shows? one in'));
    expect(
      find.textContaining('may be a contributing cause'),
      findsNWidgets(signals.evaluate().length),
    );
  });

  testWidgets('4 students: everything hidden, no percentages', (
    tester,
  ) async {
    final (services, session) = await _session(4);
    await _show(tester, services, session);
    expect(find.textContaining('hidden to protect privacy'), findsWidgets);
    expect(find.textContaining('% correct'), findsNothing);
  });

  testWidgets('no answers yet: waiting message', (tester) async {
    final (services, session) = await _session(0);
    await _show(tester, services, session);
    expect(find.textContaining('appears once at least 5'), findsOneWidget);
  });

  testWidgets('the session screen shows the panel under the counter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BouslaApp(
        services: AppServices.inMemory(initialLocale: const Locale('en')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveInsightsPanel), findsOneWidget);
  });
}
