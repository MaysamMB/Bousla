// "Test my understanding again" from My profile: each saved session with
// concepts to review has the button; it opens that session's feedback page
// (or, when that cannot be read in this browser, the results saved in the
// profile), where the student ticks and starts the private follow-up.
import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/practice_quiz_generator.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ai implements PracticeQuizGenerator {
  @override
  String get modelName => 'fake-gemini';

  @override
  Future<List<GeneratedQuestion>> practiceQuestions({
    required List<DraftingConcept> concepts,
  }) async =>
      [
        for (final c in concepts)
          GeneratedQuestion(
            conceptIds: [c.id],
            prompt: LocalizedText(ar: 'سؤال', en: 'About ${c.name.en}?'),
            options: [
              for (final o in ['a', 'b', 'c', 'd'])
                GeneratedOption(
                    id: o, text: LocalizedText(ar: o, en: 'Option $o')),
            ],
            correctOptionId: 'a',
          ),
      ];
}

StudentFeedback _feedback(MasteryState pkState) => StudentFeedback(
      language: Language.en,
      concepts: [
        FeedbackConcept(
            conceptId: 'primary_key',
            name: const LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
            state: pkState,
            attempts: 3,
            correct: pkState == MasteryState.demonstratedMastery ? 3 : 1),
      ],
    );

/// A released session; its feedback belongs to [feedbackOwner]; the linked
/// student ("participant") saved it in their profile.
Future<(AppServices, Session)> _setUp({
  MasteryState pkState = MasteryState.possibleDifficulty,
  String feedbackOwner = 'participant',
}) async {
  final content = InMemoryContentRepository();
  final sessions = InMemorySessionRepository();
  final services = AppServices(
    content: content,
    sessions: sessions,
    practiceQuizGenerator: _Ai(),
    initialLocale: const Locale('en'),
  );
  final session = await sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: const [QuestionRef('db_pk_001', 1)],
  );
  await sessions.closeSession(session.id);
  await sessions.saveFeedback(session.id, {feedbackOwner: _feedback(pkState)});
  await sessions.releaseFeedback(session.id);
  final account = await services.auth.linkStudentAccount();
  await services.profiles.create(account.uid);
  await services.profiles.saveSession(account.uid, session, _feedback(pkState));
  return (services, session);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _openProfile(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BouslaApp(services: services));
  await _settle(tester);
  Navigator.of(tester.element(find.byType(Scaffold).first)).pushNamed('/me');
  await _settle(tester);
}

void main() {
  testWidgets('the button opens the feedback page; the test starts from it',
      (tester) async {
    final (services, session) = await _setUp();
    await _openProfile(tester, services);
    final button = find.byKey(ValueKey('profile-test-again-${session.id}'));
    expect(button, findsOneWidget);
    expect(
        find.descendant(
            of: button, matching: find.text('Test My Understanding Again')),
        findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
    expect(find.byType(FeedbackScreen), findsOneWidget);
    expect(find.text('May need review'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('follow-up-start')));
    await _settle(tester);
    expect(find.text('About Primary Key?'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-up-ai-label')), findsOneWidget);
  });

  testWidgets('no concept to review: no button', (tester) async {
    final (services, session) =
        await _setUp(pkState: MasteryState.demonstratedMastery);
    await _openProfile(tester, services);
    expect(find.byKey(ValueKey('session-${session.id}')), findsOneWidget);
    expect(
        find.byKey(ValueKey('profile-test-again-${session.id}')), findsNothing);
  });

  testWidgets(
      'saved from another browser: the profile\'s results are used, '
      'and the test still works', (tester) async {
    final (services, session) = await _setUp(feedbackOwner: 'other-browser');
    await _openProfile(tester, services);
    final button = find.byKey(ValueKey('profile-test-again-${session.id}'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
    // Not "feedback not available": the saved results, with the tick.
    expect(find.byKey(const ValueKey('concept-primary_key')), findsOneWidget);
    expect(find.text('You answered 1 of 3 correctly'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('follow-up-start')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('follow-up-option-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('follow-up-submit')));
    await _settle(tester);
    expect(find.text('Before review: 1 of 3'), findsOneWidget);
    expect(find.text('After review: 1 of 1'), findsOneWidget);
    expect(find.text('Your understanding appears to have improved'),
        findsOneWidget);
  });
}
