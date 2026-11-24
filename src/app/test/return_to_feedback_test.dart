import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A closed session; [released] and feedback saved for this browser's
/// account ('participant' in the in-memory auth) as asked.
Future<(AppServices, Session)> _setUp({
  required bool released,
  required bool feedbackForMe,
}) async {
  final services = AppServices.inMemory(initialLocale: const Locale('en'));
  final questions = await services.content.listQuestions('database_systems');
  final session = await services.sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  final me = await services.auth.ensureParticipant();
  if (feedbackForMe) {
    await services.sessions.saveFeedback(session.id, {
      me: StudentFeedback(
        language: Language.en,
        concepts: const [
          FeedbackConcept(
            conceptId: 'primary_key',
            name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
            state: MasteryState.possibleDifficulty,
            attempts: 2,
            correct: 0,
          ),
        ],
      ),
    });
  }
  await services.sessions.closeSession(session.id);
  if (released) await services.sessions.releaseFeedback(session.id);
  return (services, session);
}

Future<void> _openLink(
  WidgetTester tester,
  AppServices services,
  Session session,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BouslaApp(services: services));
  await tester.pumpAndSettle();
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .pushNamed('/join/${session.code}');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Join'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('closed + released: the link opens my feedback and map', (
    tester,
  ) async {
    final (services, session) = await _setUp(
      released: true,
      feedbackForMe: true,
    );
    await _openLink(tester, services, session);
    expect(find.text('Your feedback'), findsOneWidget);
    expect(find.text('Your knowledge map for this session'), findsOneWidget);
    expect(find.text('Primary Key'), findsOneWidget);
  });

  testWidgets('closed, not released yet: still "session closed"', (
    tester,
  ) async {
    final (services, session) = await _setUp(
      released: false,
      feedbackForMe: true,
    );
    await _openLink(tester, services, session);
    expect(find.text('Your feedback'), findsNothing);
    expect(find.textContaining('closed'), findsWidgets);
  });

  testWidgets('released, but nothing for this browser: says where to look', (
    tester,
  ) async {
    final (services, session) = await _setUp(
      released: true,
      feedbackForMe: false,
    );
    await _openLink(tester, services, session);
    expect(
      find.textContaining('There is no feedback for you in this session'),
      findsOneWidget,
    );
  });
}
