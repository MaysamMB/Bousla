// "Test my understanding again": the student's private reassessment after a
// session, on new questions the instructor app reserved for them when it
// published feedback; made and graded without any instructor action, then
// compared with the original results. The Firestore side (rules: owner,
// reserved questions only, no bank listing, grading against the answer key,
// no instructor access) is tested in firebase/test/rules.test.mjs.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_follow_up_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/feedback_publisher.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/follow_up_repository.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/features/student_web/feedback/follow_up_screen.dart';
import 'package:bousla_app/features/student_web/feedback/review_marks_store.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// "This browser" in the in-memory services.
const _me = 'participant';

FeedbackConcept _concept(String id, String ar, String en, MasteryState state,
        int attempts, int correct) =>
    FeedbackConcept(
      conceptId: id,
      name: LocalizedText(ar: ar, en: en),
      state: state,
      attempts: attempts,
      correct: correct,
    );

StudentFeedback _feedback(Language language) => StudentFeedback(
      language: language,
      concepts: [
        _concept('primary_key', 'المفتاح الأساسي', 'Primary Key',
            MasteryState.possibleDifficulty, 3, 1),
        _concept('foreign_key', 'المفتاح الخارجي', 'Foreign Key',
            MasteryState.emerging, 2, 1),
        _concept('relational_model', 'النموذج العلائقي', 'Relational Model',
            MasteryState.demonstratedMastery, 2, 2),
      ],
      // As the instructor app reserves them: new questions only (the
      // session asked db_pk_001).
      reassessment: const [
        ReassessmentQuestion(
            questionId: 'db_pk_002', version: 1, conceptId: 'primary_key'),
        ReassessmentQuestion(
            questionId: 'db_fk_001', version: 1, conceptId: 'foreign_key'),
        ReassessmentQuestion(
            questionId: 'db_fk_002', version: 1, conceptId: 'foreign_key'),
      ],
      recommendations: const [
        FeedbackRecommendation(
          conceptId: 'primary_key',
          reason: RecommendationReason.reviewConcept,
          resources: [
            FeedbackResource(
              id: 'res_pk',
              title: LocalizedText(ar: 'شرح', en: 'Primary keys explained'),
              type: ResourceType.activity,
            ),
          ],
        ),
      ],
    );

class _World {
  _World(this.content, this.sessions, this.session, this.services);

  final InMemoryContentRepository content;
  final InMemorySessionRepository sessions;
  final Session session;
  final AppServices services;

  InMemoryFollowUpRepository get followUps =>
      services.followUps! as InMemoryFollowUpRepository;

  /// The same backend, as another student would reach it.
  InMemoryFollowUpRepository asStudent(String uid) =>
      InMemoryFollowUpRepository(
        content: content,
        sessions: sessions,
        currentUser: () async => uid,
      );
}

/// A released session that asked db_pk_001; [_me] has [_feedback].
Future<_World> _world({Language language = Language.en}) async {
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
      displayLanguage: language,
    ),
  );
  await sessions.closeSession(session.id);
  await sessions.saveFeedback(session.id, {_me: _feedback(language)});
  await sessions.releaseFeedback(session.id);
  final services = AppServices(
    content: content,
    sessions: sessions,
    initialLocale: Locale(language.name),
  );
  return _World(content, sessions, session, services);
}

Future<void> _pump(WidgetTester tester, _World w, Widget home,
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
      home: home,
    ),
  ));
  await _settle(tester);
}

/// The in-memory streams complete on the real event loop.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

ReviewMarksStore _memoryStore() {
  final values = <String, String>{};
  return ReviewMarksStore(
      read: (k) => values[k], write: (k, v) => values[k] = v);
}

Widget _feedbackScreen(_World w) => FeedbackScreen(
      sessionId: w.session.id,
      participantId: _me,
      reviewStore: _memoryStore(),
    );

final _start = find.byKey(const ValueKey('follow-up-start'));
final _submit = find.byKey(const ValueKey('follow-up-submit'));

Future<void> _answer(WidgetTester tester, String optionId) async {
  await tester.tap(find.byKey(ValueKey('follow-up-option-$optionId')));
  await tester.pump();
  await tester.tap(_submit);
  await _settle(tester);
}

void main() {
  group('reserving new questions at publish (instructor app, no action)', () {
    Question q(String id, String concept) => Question(
        id: id, version: 1, conceptIds: [concept], optionIds: const ['a', 'b']);
    AnswerKey key(String id) =>
        AnswerKey(questionId: id, questionVersion: 1, correctOptionId: 'a');
    Response wrong(String student, String id) => Response(
        participantId: student,
        questionId: id,
        questionVersion: 1,
        selectedOptionId: 'b',
        displayLanguage: Language.en);

    test('new questions on the concepts to review only, never a repeat',
        () async {
      final concepts =
          await InMemoryContentRepository().listConcepts('database_systems');
      final asked = [q('pk_1', 'primary_key'), q('pk_2', 'primary_key')];
      final bank = [
        ...asked,
        q('pk_3', 'primary_key'),
        q('pk_4', 'primary_key'),
        q('pk_5', 'primary_key'),
        q('rm_1', 'relational_model'),
      ];
      final out = computeFeedback(
        responses: [wrong('s1', 'pk_1'), wrong('s1', 'pk_2')],
        questions: asked,
        keys: [for (final x in bank) key(x.id)],
        concepts: concepts,
        resources: const [],
        bank: bank,
      );
      final fb = out['s1']!.feedback;
      expect(fb.reviewConceptIds, ['primary_key']);
      expect([for (final r in fb.reassessment) (r.key, r.conceptId)],
          [('pk_3_v1', 'primary_key'), ('pk_4_v1', 'primary_key')]);
      // Stored for the rules, next to the feedback.
      expect(fb.toJson()['reassessment_question_keys'], ['pk_3_v1', 'pk_4_v1']);
      expect(
          StudentFeedback.fromJson(fb.toJson()).reassessment.map((r) => r.key),
          ['pk_3_v1', 'pk_4_v1']);
      // Same states, evidence and steps as without a bank.
      final plain = computeFeedback(
        responses: [wrong('s1', 'pk_1'), wrong('s1', 'pk_2')],
        questions: asked,
        keys: [for (final x in bank) key(x.id)],
        concepts: concepts,
        resources: const [],
      )['s1']!
          .feedback;
      expect(plain.reassessment, isEmpty);
      final a = fb.toJson()
        ..remove('reassessment_questions')
        ..remove('reassessment_question_keys');
      final b = plain.toJson()
        ..remove('reassessment_questions')
        ..remove('reassessment_question_keys');
      expect(a.toString(), b.toString());
    });
  });

  group('private attempt (backend)', () {
    Future<FollowUpAttempt> start(_World w,
            {List<String> concepts = const ['primary_key'],
            StudentFeedback? feedback,
            FollowUpRepository? repo}) =>
        (repo ?? w.followUps).startAttempt(
          session: w.session,
          feedback: feedback ?? _feedback(Language.en),
          conceptIds: concepts,
          language: Language.en,
        );

    test('made for this student only, on reserved new questions, no session',
        () async {
      final w = await _world();
      final a = await start(w, concepts: ['primary_key', 'foreign_key']);
      expect(a.ownerId, _me);
      expect(a.sessionId, w.session.id);
      expect(a.id, FollowUpAttempt.idFor(_me, w.session.id));
      expect(a.conceptIds, ['primary_key', 'foreign_key']);
      expect(a.questions, const [
        QuestionRef('db_pk_002', 1),
        QuestionRef('db_fk_001', 1),
        QuestionRef('db_fk_002', 1),
      ]);
      // Never a question of the original session.
      for (final asked in w.session.questions) {
        expect(a.questions, isNot(contains(asked)));
      }
      expect(a.status, FollowUpStatus.inProgress);
      // No class session was created for it.
      expect(
          (await w.sessions.listSessions(
                  ownerId: 'teacher', courseId: 'database_systems'))
              .map((x) => x.id),
          [w.session.id]);
    });

    test('a changed copy of the feedback in the browser does not count',
        () async {
      final w = await _world();
      final tampered = StudentFeedback(
        language: Language.en,
        concepts: _feedback(Language.en).concepts,
        reassessment: const [
          ReassessmentQuestion(
              questionId: 'db_pk_001', version: 1, conceptId: 'primary_key'),
        ],
      );
      final a = await start(w, feedback: tampered);
      expect(a.questions, const [QuestionRef('db_pk_002', 1)]);
    });

    test('repeated presses make one attempt; it is resumed', () async {
      final w = await _world();
      final both = await Future.wait([start(w), start(w)]);
      expect(both[0].id, both[1].id);
      expect(w.followUps.storedAttempts, hasLength(1));
      await w.followUps.answer(both[0], const QuestionRef('db_pk_002', 1), 'b');
      final again = await start(w);
      expect(again.id, both[0].id);
      expect(
          await w.followUps.graded(again), {const QuestionRef('db_pk_002', 1)});
      expect(w.followUps.storedAttempts, hasLength(1));
    });

    test('another student cannot reach the attempt or its results', () async {
      final w = await _world();
      final mine = await start(w);
      await w.followUps.answer(mine, const QuestionRef('db_pk_002', 1), 'b');
      final other = w.asStudent('someone-else');
      expect(await other.findAttempt(w.session.id), isNull);
      await expectLater(
          other.questions(mine), throwsA(isA<FollowUpAccessDenied>()));
      await expectLater(
          other.grades(mine), throwsA(isA<FollowUpAccessDenied>()));
      await expectLater(
          other.answer(mine, const QuestionRef('db_pk_002', 1), 'a'),
          throwsA(isA<FollowUpAccessDenied>()));
      await expectLater(
          other.finish(mine), throwsA(isA<FollowUpAccessDenied>()));
      // Nor make one from this student's feedback.
      await expectLater(
          start(w, repo: other),
          throwsA(isA<FollowUpUnavailable>()
              .having((e) => e.problem, 'problem', FollowUpProblem.notOwner)));
    });

    test('only concepts the feedback says need review', () async {
      final w = await _world();
      for (final concepts in [
        ['relational_model'],
        ['primary_key', 'relational_model'],
      ]) {
        await expectLater(
            start(w, concepts: concepts),
            throwsA(isA<FollowUpUnavailable>().having(
                (e) => e.problem, 'problem', FollowUpProblem.notEligible)));
      }
      final a = await start(w);
      // A question that is not in the attempt is refused.
      await expectLater(
          w.followUps.answer(a, const QuestionRef('db_fk_001', 1), 'c'),
          throwsA(isA<FollowUpAccessDenied>()));
    });

    test('graded by the backend; an answer cannot be changed or re-graded',
        () async {
      final w = await _world();
      final a = await start(w, concepts: ['primary_key', 'foreign_key']);
      // db_pk_002's key is b: answer a (wrong), then try to change to b.
      await w.followUps.answer(a, const QuestionRef('db_pk_002', 1), 'a');
      await w.followUps.answer(a, const QuestionRef('db_pk_002', 1), 'b');
      final grades = await w.followUps.grades(a);
      expect(grades, hasLength(1));
      expect(grades.single.correct, isFalse);
      expect(grades.single.conceptIds, ['primary_key']);
      // Finished: no more answers.
      final done = await w.followUps.finish(a);
      expect(done.status, FollowUpStatus.finished);
      await expectLater(
          w.followUps.answer(done, const QuestionRef('db_fk_001', 1), 'c'),
          throwsA(isA<FollowUpAccessDenied>()));
    });

    test('the original results are never touched', () async {
      final w = await _world();
      final a = await start(w);
      await w.followUps.answer(a, const QuestionRef('db_pk_002', 1), 'b');
      await w.followUps.finish(a);
      final fb = w.sessions.releasedFeedback(w.session.id, _me)!;
      expect(
          fb.concepts.map((c) => (c.conceptId, c.state, c.correct, c.attempts)),
          _feedback(Language.en)
              .concepts
              .map((c) => (c.conceptId, c.state, c.correct, c.attempts)));
      final responses = await w.sessions.watchResponses(w.session.id).first;
      expect(responses, hasLength(1));
    });
  });

  group('screens', () {
    testWidgets(
        'tick, press, answer a new question, see the comparison, go back',
        (tester) async {
      final w = await _world();
      await _pump(tester, w, _feedbackScreen(w));
      // Disabled until a concept is ticked.
      expect(tester.widget<ButtonStyleButton>(_start).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
      await tester.pump();
      await tester.tap(_start);
      await _settle(tester);

      // The reassessment: no code, no teacher.
      expect(find.text('Follow-up test'), findsOneWidget);
      expect(find.textContaining('Only you see it'), findsOneWidget);
      expect(find.textContaining('code'), findsNothing);
      expect(find.text('Question 1 of 1'), findsOneWidget);
      await _answer(tester, 'b'); // db_pk_002: right

      // Results: from the graded answer and the original 1 of 3.
      expect(find.text('Your follow-up results'), findsOneWidget);
      expect(
          find.text('Concepts tested: 1 · appear improved: 1 · '
              'may still need review: 0'),
          findsOneWidget);
      final pk = find.byKey(const ValueKey('follow-up-concept-primary_key'));
      for (final t in [
        'Before review: 1 of 3',
        'After review: 1 of 1',
        'Your understanding appears to have improved',
      ]) {
        expect(find.descendant(of: pk, matching: find.text(t)), findsOneWidget,
            reason: t);
      }
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('follow-up-diff-primary_key')))
              .data,
          contains('+67'));
      for (final word in ['Mastered', 'mastered', 'Verified', 'Confirmed']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(find.textContaining('not a final judgement'), findsOneWidget);

      // Back to the feedback page: the button now shows the results.
      await tester.tap(find.byKey(const ValueKey('follow-up-back')));
      await _settle(tester);
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(find.text('See my follow-up results'), findsOneWidget);
      // The feedback still says what it said.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('concept-primary_key')),
              matching: find.text('May need review')),
          findsOneWidget);
    });

    testWidgets('a wrong answer: no improvement claimed, whatever was ticked',
        (tester) async {
      final w = await _world();
      await _pump(tester, w, _feedbackScreen(w));
      await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
      await tester.pump();
      await tester.tap(_start);
      await _settle(tester);
      await _answer(tester, 'a'); // wrong (key b)
      expect(
          find.text('Concepts tested: 1 · appear improved: 0 · '
              'may still need review: 1'),
          findsOneWidget);
      expect(find.text('After review: 0 of 1'), findsOneWidget);
      expect(find.text('Fewer correct this time'), findsOneWidget);
      expect(find.byKey(const ValueKey('follow-up-review-primary_key')),
          findsOneWidget);
      expect(find.textContaining('appears to have improved'), findsNothing);
    });

    testWidgets('leaving half-way and coming back resumes the same attempt',
        (tester) async {
      final w = await _world();
      await _pump(tester, w, _feedbackScreen(w));
      await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
      await tester.tap(find.byKey(const ValueKey('reviewed-foreign_key')));
      await tester.pump();
      await tester.tap(_start);
      await _settle(tester);
      expect(find.text('Question 1 of 3'), findsOneWidget);
      await _answer(tester, 'b');
      await tester.pageBack();
      await _settle(tester);
      expect(find.text('Continue my follow-up test'), findsOneWidget);
      await tester.tap(_start);
      await _settle(tester);
      expect(find.text('Question 2 of 3'), findsOneWidget);
      expect(w.followUps.storedAttempts, hasLength(1));
    });

    testWidgets('another student in this browser: no attempt, no comparison',
        (tester) async {
      final w = await _world();
      await _pump(
        tester,
        w,
        FollowUpScreen(
          sessionId: w.session.id,
          participantId: 'the-student-who-answered',
          feedback: _feedback(Language.en),
          reviewedConceptIds: const ['primary_key'],
        ),
      );
      expect(
          find.byKey(const ValueKey('follow-up-unavailable')), findsOneWidget);
      expect(find.textContaining('cannot be linked reliably'), findsOneWidget);
      expect(find.textContaining('Before review'), findsNothing);
      expect(w.followUps.storedAttempts, isEmpty);
    });

    testWidgets('no new question reserved for the concept: says so',
        (tester) async {
      final w = await _world();
      final feedback = StudentFeedback(
        language: Language.en,
        concepts: [
          _concept('normalization', 'التطبيع', 'Normalization',
              MasteryState.possibleDifficulty, 2, 0),
        ],
      );
      await w.sessions.saveFeedback(w.session.id, {_me: feedback});
      await _pump(
        tester,
        w,
        FollowUpScreen(
          sessionId: w.session.id,
          participantId: _me,
          feedback: feedback,
          reviewedConceptIds: const ['normalization'],
        ),
      );
      expect(
          find.byKey(const ValueKey('follow-up-unavailable')), findsOneWidget);
      expect(find.textContaining('There are no new questions'), findsOneWidget);
      expect(w.followUps.storedAttempts, isEmpty);
    });

    testWidgets('an error offers to try again, and trying again works',
        (tester) async {
      final w = await _world();
      final flaky = _Flaky(w.followUps);
      final services = AppServices(
        content: w.content,
        sessions: w.sessions,
        followUps: flaky,
        initialLocale: const Locale('en'),
      );
      await _pump(
        tester,
        _World(w.content, w.sessions, w.session, services),
        FollowUpScreen(
          sessionId: w.session.id,
          participantId: _me,
          feedback: _feedback(Language.en),
          reviewedConceptIds: const ['primary_key'],
        ),
      );
      expect(find.byKey(const ValueKey('follow-up-error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('follow-up-retry')));
      await _settle(tester);
      expect(find.text('Question 1 of 1'), findsOneWidget);
      expect(w.followUps.storedAttempts, hasLength(1));
    });

    testWidgets('Arabic: texts in Arabic, right to left', (tester) async {
      final w = await _world(language: Language.ar);
      await _pump(tester, w, _feedbackScreen(w), locale: 'ar');
      expect(find.text('اختبر فهمي مرة أخرى'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reviewed-primary_key')));
      await tester.pump();
      await tester.tap(_start);
      await _settle(tester);
      expect(find.text('اختبار المتابعة'), findsOneWidget);
      expect(Directionality.of(tester.element(_submit)), TextDirection.rtl);
      await _answer(tester, 'b');
      expect(find.text('نتائج اختبار المتابعة'), findsOneWidget);
      expect(find.text('يبدو أن فهمك تحسّن'), findsOneWidget);
      expect(find.text('قبل المراجعة: 1 من 3'), findsOneWidget);
      expect(find.text('بعد المراجعة: 1 من 1'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('يبدو أن فهمك تحسّن'))),
          TextDirection.rtl);
    });
  });
}

/// Fails the first start, as a lost connection would.
class _Flaky implements FollowUpRepository {
  _Flaky(this._inner);

  final FollowUpRepository _inner;
  var _failed = false;

  @override
  Future<FollowUpAttempt> startAttempt({
    required Session session,
    required StudentFeedback feedback,
    required List<String> conceptIds,
    required Language language,
  }) {
    if (!_failed) {
      _failed = true;
      throw StateError('offline');
    }
    return _inner.startAttempt(
        session: session,
        feedback: feedback,
        conceptIds: conceptIds,
        language: language);
  }

  @override
  Future<FollowUpAttempt?> findAttempt(String sessionId) =>
      _inner.findAttempt(sessionId);
  @override
  Future<List<QuestionView>> questions(FollowUpAttempt a) =>
      _inner.questions(a);
  @override
  Future<void> answer(FollowUpAttempt a, QuestionRef q, String o) =>
      _inner.answer(a, q, o);
  @override
  Future<Set<QuestionRef>> graded(FollowUpAttempt a) => _inner.graded(a);
  @override
  Future<List<FollowUpGrade>> grades(FollowUpAttempt a) => _inner.grades(a);
  @override
  Future<FollowUpAttempt> finish(FollowUpAttempt a) => _inner.finish(a);
}
