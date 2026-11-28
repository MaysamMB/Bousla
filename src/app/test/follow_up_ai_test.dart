// "Test my understanding again" with AI (Gemini): practice questions written
// for one student, labelled as AI, kept and graded in this browser only;
// the reserved questions are used when AI is unavailable.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/practice_quiz_generator.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_follow_up_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/features/student_web/feedback/practice_attempt.dart';
import 'package:bousla_app/features/student_web/feedback/review_marks_store.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'participant';

GeneratedQuestion _q(String concept, String en, {String correct = 'b'}) =>
    GeneratedQuestion(
      conceptIds: [concept],
      prompt: LocalizedText(ar: 'سؤال $en', en: 'Question $en?'),
      options: [
        for (final o in ['a', 'b', 'c', 'd'])
          GeneratedOption(
              id: o, text: LocalizedText(ar: 'خيار $o', en: 'Option $o')),
      ],
      correctOptionId: correct,
    );

/// Gemini in tests: returns [questions] (or throws) and records what it was
/// sent.
class _FakeAi implements PracticeQuizGenerator {
  _FakeAi(this.questions, {this.fail = false});

  final List<GeneratedQuestion> questions;
  final bool fail;
  final sent = <List<DraftingConcept>>[];

  @override
  String get modelName => 'fake-gemini';

  @override
  Future<List<GeneratedQuestion>> practiceQuestions({
    required List<DraftingConcept> concepts,
  }) async {
    sent.add(concepts);
    if (fail) throw StateError('busy');
    return questions;
  }
}

class _World {
  _World(this.services, this.sessions, this.session, this.ai, this.storage);

  final AppServices services;
  final InMemorySessionRepository sessions;
  final Session session;
  final _FakeAi ai;
  final Map<String, String> storage;

  InMemoryFollowUpRepository get followUps =>
      services.followUps! as InMemoryFollowUpRepository;

  ReviewMarksStore store() => ReviewMarksStore(
      read: (k) => storage[k], write: (k, v) => storage[k] = v);
}

Future<_World> _world(_FakeAi ai, {Language language = Language.en}) async {
  final content = InMemoryContentRepository();
  final sessions = InMemorySessionRepository();
  final session = await sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: const [QuestionRef('db_pk_001', 1)],
  );
  await sessions.submitResponse(
    session.id,
    Response(
        participantId: _me,
        questionId: 'db_pk_001',
        questionVersion: 1,
        selectedOptionId: 'b',
        displayLanguage: language),
  );
  await sessions.closeSession(session.id);
  await sessions.saveFeedback(session.id, {
    _me: StudentFeedback(
      language: language,
      concepts: const [
        FeedbackConcept(
            conceptId: 'primary_key',
            name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
            state: MasteryState.possibleDifficulty,
            attempts: 3,
            correct: 1),
        FeedbackConcept(
            conceptId: 'relational_model',
            name: LocalizedText(ar: 'النموذج العلائقي', en: 'Relational Model'),
            state: MasteryState.demonstratedMastery,
            attempts: 2,
            correct: 2),
      ],
      reassessment: const [
        ReassessmentQuestion(
            questionId: 'db_pk_002', version: 1, conceptId: 'primary_key'),
      ],
    ),
  });
  await sessions.releaseFeedback(session.id);
  final services = AppServices(
    content: content,
    sessions: sessions,
    practiceQuizGenerator: ai,
    initialLocale: Locale(language.name),
  );
  return _World(services, sessions, session, ai, {});
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _World w,
    {String locale = 'en'}) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(
    services: w.services,
    child: MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FeedbackScreen(
          sessionId: w.session.id, participantId: _me, reviewStore: w.store()),
    ),
  ));
  await _settle(tester);
}

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('follow-up-start')));
  await _settle(tester);
}

Future<void> _answer(WidgetTester tester, String optionId) async {
  await tester.tap(find.byKey(ValueKey('follow-up-option-$optionId')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('follow-up-submit')));
  await _settle(tester);
}

final _aiLabel = find.byKey(const ValueKey('follow-up-ai-label'));

void main() {
  testWidgets('Gemini writes new questions; labelled; graded; compared',
      (tester) async {
    final w =
        await _world(_FakeAi([_q('primary_key', '1'), _q('primary_key', '2')]));
    await _open(tester, w);
    await _start(tester);

    expect(_aiLabel, findsOneWidget);
    expect(find.text('Practice questions written by AI for you only'),
        findsOneWidget);
    expect(find.textContaining('Your teacher has not checked them'),
        findsOneWidget);
    expect(find.text('Question 1 of 2'), findsOneWidget);
    expect(find.text('Question 1?'), findsOneWidget);
    await _answer(tester, 'b'); // right
    await _answer(tester, 'b'); // right

    expect(_aiLabel, findsOneWidget);
    expect(find.text('Before review: 1 of 3'), findsOneWidget);
    expect(find.text('After review: 2 of 2'), findsOneWidget);
    expect(find.text('Your understanding appears to have improved'),
        findsOneWidget);
    expect(find.textContaining('Approximate comparison'), findsOneWidget);

    // Only the ticked concept, by ID and name, was sent: nothing about the
    // student.
    expect(w.ai.sent, hasLength(1));
    expect([for (final c in w.ai.sent.single) (c.id, c.name.en)],
        [('primary_key', 'Primary Key')]);
    // Nothing went to the backend; the original feedback is unchanged.
    expect(w.followUps.storedAttempts, isEmpty);
    expect(
        w.sessions.releasedFeedback(w.session.id, _me)!.concepts.first.correct,
        1);
  });

  testWidgets('wrong answers: no improvement claimed', (tester) async {
    final w = await _world(_FakeAi([_q('primary_key', '1')]));
    await _open(tester, w);
    await _start(tester);
    await _answer(tester, 'a'); // wrong
    expect(find.text('After review: 0 of 1'), findsOneWidget);
    expect(find.text('Fewer correct this time'), findsOneWidget);
    expect(find.textContaining('appears to have improved'), findsNothing);
  });

  testWidgets('leaving half-way resumes the same questions, no new request',
      (tester) async {
    final w =
        await _world(_FakeAi([_q('primary_key', '1'), _q('primary_key', '2')]));
    await _open(tester, w);
    await _start(tester);
    await _answer(tester, 'b');
    await tester.pageBack();
    await _settle(tester);
    expect(find.text('Continue my follow-up test'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-up-start')));
    await _settle(tester);
    expect(find.text('Question 2 of 2'), findsOneWidget);
    expect(find.text('Question 2?'), findsOneWidget);
    expect(w.ai.sent, hasLength(1));
    // Kept in this browser only.
    expect(w.storage.keys,
        contains(ReviewMarksStore.practiceKeyFor(w.session.id, _me)));
  });

  testWidgets('after finishing, the button shows the results again',
      (tester) async {
    final w = await _world(_FakeAi([_q('primary_key', '1')]));
    await _open(tester, w);
    await _start(tester);
    await _answer(tester, 'b');
    await tester.tap(find.byKey(const ValueKey('follow-up-back')));
    await _settle(tester);
    expect(find.text('See my follow-up results'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-up-start')));
    await _settle(tester);
    expect(find.text('After review: 1 of 1'), findsOneWidget);
    expect(w.ai.sent, hasLength(1));
  });

  testWidgets('AI fails: the reserved questions are used instead',
      (tester) async {
    final w = await _world(_FakeAi(const [], fail: true));
    await _open(tester, w);
    await _start(tester);
    expect(_aiLabel, findsNothing);
    expect(find.text('Question 1 of 1'), findsOneWidget);
    expect(w.followUps.storedAttempts, hasLength(1));
  });

  testWidgets('AI gives nothing usable: the reserved questions are used',
      (tester) async {
    final w = await _world(_FakeAi(const []));
    await _open(tester, w);
    await _start(tester);
    expect(_aiLabel, findsNothing);
    expect(w.followUps.storedAttempts, hasLength(1));
  });

  testWidgets('Arabic: AI label and caution in Arabic, right to left',
      (tester) async {
    final w =
        await _world(_FakeAi([_q('primary_key', '1')]), language: Language.ar);
    await _open(tester, w, locale: 'ar');
    await _start(tester);
    expect(find.text('أسئلة تدريبية أعدّها الذكاء الاصطناعي لك وحدك'),
        findsOneWidget);
    expect(Directionality.of(tester.element(_aiLabel)), TextDirection.rtl);
    await _answer(tester, 'b');
    expect(find.textContaining('مقارنة تقريبية'), findsOneWidget);
    expect(find.text('يبدو أن فهمك تحسّن'), findsOneWidget);
  });

  test('a damaged stored practice attempt is ignored', () {
    for (final bad in [null, 'x', '{}', '{"questions": []}']) {
      expect(PracticeAttempt.tryParse(bad), isNull, reason: bad);
    }
    final p = PracticeAttempt(
        model: 'm',
        conceptIds: const ['primary_key'],
        questions: [_q('primary_key', '1')]);
    p.answers[0] = 'b';
    final back = PracticeAttempt.tryParse(p.toJson())!;
    expect(back.answers, {0: 'b'});
    expect(back.grades.single.correct, isTrue);
  });
}
