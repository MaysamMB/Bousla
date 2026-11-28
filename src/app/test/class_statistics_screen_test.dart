// The class statistics page: the same LiveInsightsPanel the session screen
// used to show, now on its own page. Same data, same calculations.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/sessions/class_statistics_screen.dart';
import 'package:bousla_app/features/instructor/sessions/live_insights_panel.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session of the sample course where [students] students answer every
/// question with a wrong option (as in live_insights_panel_test.dart).
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
          displayLanguage: Language.en,
        ),
      );
    }
  }
  return (services, session);
}

Future<void> _pump(
  WidgetTester tester,
  AppServices services,
  Widget home, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(900, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every text the panel shows, in order.
List<String> _panelTexts(WidgetTester tester) => [
      for (final e in find
          .descendant(
            of: find.byType(LiveInsightsPanel),
            matching: find.byType(Text),
          )
          .evaluate())
        (e.widget as Text).data ??
            (e.widget as Text).textSpan?.toPlainText() ??
            '',
    ];

void main() {
  testWidgets('shows exactly what the panel showed on the session screen',
      (tester) async {
    final (services, session) = await _session(5);

    // The panel alone, as it used to be embedded in the session screen.
    await _pump(
      tester,
      services,
      Scaffold(
        body: SingleChildScrollView(child: LiveInsightsPanel(session: session)),
      ),
    );
    final before = _panelTexts(tester);
    expect(before, contains('What the class understands'));
    expect(before.any((t) => t.contains('5 answered · 0% correct')), isTrue);

    // The same panel on the new page.
    await _pump(tester, services, ClassStatisticsScreen(session: session));
    expect(find.text('Class statistics'), findsOneWidget);
    expect(_panelTexts(tester), before);
  });

  testWidgets('Arabic: title in Arabic, right to left', (tester) async {
    final (services, session) = await _session(5);
    await _pump(
      tester,
      services,
      ClassStatisticsScreen(session: session),
      locale: 'ar',
    );
    expect(find.text('إحصائيات الصف'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(LiveInsightsPanel))),
      TextDirection.rtl,
    );
  });

  testWidgets('no answers yet: the page opens and says it is waiting',
      (tester) async {
    final (services, session) = await _session(0);
    await _pump(tester, services, ClassStatisticsScreen(session: session));
    expect(find.text('Class statistics'), findsOneWidget);
    expect(find.textContaining('appears once at least'), findsOneWidget);
  });
}
