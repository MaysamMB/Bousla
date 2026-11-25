import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback_publisher.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/resource_review.dart';
import 'package:bousla_app/features/instructor/resources/session_resources_card.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

/// A session of the sample course; [wrong] students answer every question
/// wrong.
Future<(AppServices, Session, List<String>)> _session({int wrong = 0}) async {
  final services = AppServices.inMemory(initialLocale: const Locale('en'));
  final questions = await services.content.listQuestions(_course);
  final keys = await services.content.answerKeys(_course);
  final session = await services.sessions.createSession(
    courseId: _course,
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  final students = <String>[];
  for (var s = 0; s < wrong; s++) {
    final id = await services.sessions.join(session.id);
    students.add(id);
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
  return (services, session, students);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('lists the session concepts and adds a missing resource',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (services, session, _) = await _session();
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
            body: SingleChildScrollView(
              child: SessionResourcesCard(session: session),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Resources for this session'), findsOneWidget);
    expect(find.textContaining('no approved resource'), findsOneWidget);
    final fk = find.byKey(const ValueKey('session-res-foreign_key'));
    expect(
      find.descendant(of: fk, matching: find.text('No approved resource')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: fk, matching: find.text('Add resource')),
    );
    await tester.pumpAndSettle();
    // The concept is already chosen.
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Foreign Key'),
    );
    expect(chip.selected, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Foreign keys in 5 minutes',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'https://example.edu/fk',
    );
    await tester.tap(find.text('Save and approve'));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: fk, matching: find.text('1 approved resource')),
      findsOneWidget,
    );
  });

  test('a resource added after closing reaches the published feedback',
      () async {
    final (services, session, students) = await _session(wrong: 1);
    await services.sessions.closeSession(session.id);
    final saved = await services.content.saveResource(
      _course,
      const ResourceDraft(
        conceptIds: ['foreign_key'],
        type: ResourceType.video,
        language: ResourceLanguage.en,
        titleText: 'Foreign keys in 5 minutes',
        url: 'https://example.edu/fk',
      ),
    );
    await FeedbackPublisher(
      content: services.content,
      sessions: services.sessions,
    ).publish(session);
    final feedback = await services.sessions
        .watchMyFeedback(session.id, students.single)
        .first;
    expect(
      feedback!.recommendations.expand((r) => r.resources).map((r) => r.id),
      contains(saved.id),
    );
  });
}
