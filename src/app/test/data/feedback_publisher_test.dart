import 'package:bousla_app/data/ai/feedback_explainer.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/feedback_publisher.dart';
import 'package:bousla_app/data/firebase/firestore_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/session_repository.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

// Anonymous-looking UIDs, long enough to be searched for in the prompt.
const _a = 'uidAnonAAAA1111';
const _b = 'uidAnonBBBB2222';
const _c = 'uidAnonCCCC3333';

/// Records the order of the calls that matter for publishing.
class _RecordingSessions extends InMemorySessionRepository {
  final log = <String>[];
  var failSave = false;

  @override
  Future<void> saveFeedback(
    String sessionId,
    Map<String, StudentFeedback> byParticipant,
  ) async {
    log.add('save');
    if (failSave) throw StateError('offline');
    await super.saveFeedback(sessionId, byParticipant);
  }

  @override
  Future<void> releaseFeedback(String sessionId) async {
    log.add('release');
    await super.releaseFeedback(sessionId);
  }
}

/// Instead of Gemini: a fixed answer (or error), and what it was asked.
class _FakeExplainer implements FeedbackExplainer {
  _FakeExplainer({this.answer, this.error});

  final String Function(List<ExplanationProfile> profiles)? answer;
  final Object? error;
  var calls = 0;
  String? prompt;
  List<ExplanationProfile>? profiles;

  @override
  Future<ExplainerAnswer> explain(List<ExplanationProfile> profiles) async {
    calls++;
    this.profiles = profiles;
    prompt = buildFeedbackExplanationPrompt(profiles);
    if (error != null) throw error!;
    return ExplainerAnswer(text: answer!(profiles), model: 'fake-gemini');
  }
}

const _okAr = 'شكرًا لمشاركتك في هذه الجلسة. الخطوات التالية قد تساعدك على التقدّم.';
const _okEn =
    'Thank you for taking part in this session. The next steps may help you move forward.';

String _validFor(List<ExplanationProfile> profiles) => '[${[
      for (final p in profiles)
        '{"profile_id": "${p.id}", "text_ar": "$_okAr", "text_en": "$_okEn"}',
    ].join(',')}]';

Response _r(String p, String q, String option, Language lang) => Response(
      participantId: p,
      questionId: q,
      questionVersion: 1,
      selectedOptionId: option,
      displayLanguage: lang,
    );

/// Sample keys: pk_001 a, pk_002 b, fk_001 c, fk_002 a.
/// _a (Arabic) and _b (English) answer everything wrong: the same results.
/// _c answers everything right, mostly in English.
List<Response> _responses() => [
      for (final (p, lang) in [(_a, Language.ar), (_b, Language.en)]) ...[
        _r(p, 'db_pk_001', 'b', lang),
        _r(p, 'db_pk_002', 'a', lang),
        _r(p, 'db_fk_001', 'a', lang),
        _r(p, 'db_fk_002', 'b', lang),
      ],
      _r(_c, 'db_pk_001', 'a', Language.en),
      _r(_c, 'db_pk_002', 'b', Language.en),
      _r(_c, 'db_fk_001', 'c', Language.ar),
      _r(_c, 'db_fk_002', 'a', Language.en),
    ];

Future<Session> _answeredSession(
  InMemoryContentRepository content,
  SessionRepository sessions,
) async {
  final questions = await content.listQuestions(_course);
  final session = await sessions.createSession(
    courseId: _course,
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  for (final r in _responses()) {
    await sessions.submitResponse(session.id, r);
  }
  await sessions.closeSession(session.id);
  return session;
}

void main() {
  late InMemoryContentRepository content;
  late _RecordingSessions sessions;
  late Session session;

  setUp(() async {
    content = InMemoryContentRepository();
    sessions = _RecordingSessions();
    session = await _answeredSession(content, sessions);
  });

  Future<StudentFeedback?> mine(String participant) =>
      sessions.watchMyFeedback(session.id, participant).first;

  test('feedback language: most frequent display language, tie → Arabic', () {
    expect(
      feedbackLanguage([
        _r('p', 'q1', 'a', Language.en),
        _r('p', 'q2', 'a', Language.ar),
        _r('p', 'q3', 'a', Language.en),
      ]),
      Language.en,
    );
    expect(
      feedbackLanguage([
        _r('p', 'q1', 'a', Language.en),
        _r('p', 'q2', 'a', Language.ar),
      ]),
      Language.ar,
    );
  });

  test('computeFeedback uses the engine results, approved resources only',
      () async {
    final questions = await content.questionsForSession(
      session.courseId,
      session.questions,
    );
    final computed = computeFeedback(
      responses: _responses(),
      questions: [for (final q in questions) q.question],
      keys: await content.answerKeys(_course),
      concepts: await content.listConcepts(_course),
      resources: [
        ...await content.listResources(_course),
        const Resource(
          id: 'res_unreviewed',
          conceptIds: ['primary_key'],
          type: ResourceType.link,
          language: ResourceLanguage.both,
          title: LocalizedText(ar: 'غير معتمد', en: 'Unreviewed'),
          url: 'https://example.com/unreviewed',
          status: ReviewStatus.pendingReview,
        ),
      ],
    );
    expect(computed.keys, unorderedEquals([_a, _b, _c]));
    final a = computed[_a]!.feedback;
    expect(a.language, Language.ar);
    expect(computed[_b]!.feedback.language, Language.en);
    expect(computed[_c]!.feedback.language, Language.en);
    final states = {for (final c in a.concepts) c.conceptId: c};
    expect(states['primary_key']!.state, MasteryState.possibleDifficulty);
    expect(states['primary_key']!.attempts, 2);
    expect(states['primary_key']!.correct, 0);
    // A prerequisite outside the session's questions is listed, unassessed.
    expect(states['relational_model']!.state, MasteryState.insufficientEvidence);
    expect(states['relational_model']!.attempts, 0);
    expect(
      a.hints.map((h) => (h.prerequisiteId, h.signal)),
      contains(('primary_key', PrerequisiteSignal.possibleContributingGap)),
    );
    expect(a.recommendations.first.conceptId, 'primary_key');
    expect(a.recommendations.first.reason,
        RecommendationReason.reviewPrerequisite);
    final resourceIds = {
      for (final r in a.recommendations)
        for (final res in r.resources) res.id,
    };
    expect(resourceIds, contains('res_primary_key_practice'));
    expect(resourceIds, isNot(contains('res_unreviewed')));
    // Arabic and English answers with the same choices: same results.
    expect(computed[_a]!.profile.signature, computed[_b]!.profile.signature);
    final json = a.toJson().toString();
    expect(json, isNot(contains('selected_option_id')));
    expect(json, isNot(contains('correct_option_id')));
    expect(json, isNot(contains(_a)));
  });

  test('without AI: every document is saved before feedback is released',
      () async {
    final explainer = _FakeExplainer(answer: _validFor);
    final result = await FeedbackPublisher(
      content: content,
      sessions: sessions,
      explainer: explainer,
    ).publish(session, useAi: false);
    expect(sessions.log, ['save', 'release']);
    expect(explainer.calls, 0);
    expect(result.students, 3);
    expect(result.aiStudents, 0);
    for (final p in [_a, _b, _c]) {
      final f = (await mine(p))!;
      expect(f.explanation!.source, ExplanationSource.template);
      expect(f.explanation!.model, isNull);
      expect(f.explanation!.text.ar, isNotEmpty);
    }
  });

  test('a failed save releases nothing', () async {
    sessions.failSave = true;
    await expectLater(
      FeedbackPublisher(content: content, sessions: sessions)
          .publish(session),
      throwsA(isA<FeedbackPublishException>()),
    );
    expect(sessions.log, ['save']);
    final current = await sessions.watchSession(session.id).first;
    expect(current.feedbackReleased, isFalse);
    expect(await mine(_a), isNull);
  });

  test('Gemini failure: template explanations, still published', () async {
    final explainer = _FakeExplainer(
      error: const QuestionGenerationException(GenerationProblem.busy),
    );
    final result = await FeedbackPublisher(
      content: content,
      sessions: sessions,
      explainer: explainer,
    ).publish(session, useAi: true);
    expect(explainer.calls, 1);
    expect(result.aiProblem, GenerationProblem.busy);
    expect(result.aiStudents, 0);
    expect(sessions.log, ['save', 'release']);
    final f = (await mine(_a))!;
    expect(f.explanation!.source, ExplanationSource.template);
    expect(f.explanation!.model, isNull);
  });

  test('AI success: one request for unique anonymous profiles, saved as ai',
      () async {
    final explainer = _FakeExplainer(answer: _validFor);
    final result = await FeedbackPublisher(
      content: content,
      sessions: sessions,
      explainer: explainer,
    ).publish(session, useAi: true);
    expect(explainer.calls, 1);
    // _a and _b have the same results: 2 profiles for 3 students.
    expect(explainer.profiles, hasLength(2));
    expect(result.profiles, 2);
    for (final uid in [_a, _b, _c]) {
      expect(explainer.prompt, isNot(contains(uid)));
    }
    expect(result.aiStudents, 3);
    expect(result.model, 'fake-gemini');
    for (final p in [_a, _b, _c]) {
      final f = (await mine(p))!;
      expect(f.explanation!.source, ExplanationSource.ai);
      expect(f.explanation!.model, 'fake-gemini');
      expect(f.explanation!.text.en, _okEn);
    }
  });

  test('AI text failing a guard is replaced by the template', () async {
    final explainer = _FakeExplainer(
      answer: (profiles) => '[${[
        for (final p in profiles)
          p.concepts.any((c) => c.state == MasteryState.possibleDifficulty)
              ? '{"profile_id": "${p.id}", "text_ar": "لديك فجوة في المفاتيح.", "text_en": "You have a gap. See https://invented.example.com"}'
              : '{"profile_id": "${p.id}", "text_ar": "$_okAr", "text_en": "$_okEn"}',
      ].join(',')}]',
    );
    final result = await FeedbackPublisher(
      content: content,
      sessions: sessions,
      explainer: explainer,
    ).publish(session, useAi: true);
    expect(result.guardRejected, 1);
    expect(result.aiStudents, 1);
    final a = (await mine(_a))!;
    expect(a.explanation!.source, ExplanationSource.template);
    expect(a.explanation!.text.ar, isNot(contains('فجوة')));
    final c = (await mine(_c))!;
    expect(c.explanation!.source, ExplanationSource.ai);
  });

  test('on Firestore: documents with source, model and server time',
      () async {
    final db = FakeFirebaseFirestore();
    final firestore =
        FirestoreSessionRepository(db, ensureParticipant: () async => _a);
    final s = await _answeredSession(content, firestore);
    final result = await FeedbackPublisher(
      content: content,
      sessions: firestore,
      explainer: _FakeExplainer(answer: _validFor),
    ).publish(s, useAi: true);
    expect(result.students, 3);
    final doc = await db.doc('sessions/${s.id}/feedback/$_a').get();
    final data = doc.data()!;
    expect(data.containsKey('created_at'), isTrue);
    expect(data['language'], 'ar');
    expect((data['explanation'] as Map)['source'], 'ai');
    expect((data['explanation'] as Map)['model'], 'fake-gemini');
    final text = data.toString();
    expect(text, isNot(contains('selected_option_id')));
    expect(text, isNot(contains('correct_option_id')));
    expect(text, isNot(contains(_a)));
    expect((await db.doc('sessions/${s.id}').get()).data()!['feedback_released'],
        isTrue);
    final seen = await firestore.watchMyFeedback(s.id, _a).first;
    expect(seen!.concepts, isNotEmpty);
  });
}
