import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/firebase/firestore_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/session_repository.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

StudentFeedback _feedback(Language language) => StudentFeedback(
      language: language,
      concepts: const [
        FeedbackConcept(
          conceptId: 'foreign_key',
          name: LocalizedText(ar: 'المفتاح الخارجي', en: 'Foreign Key'),
          state: MasteryState.possibleDifficulty,
          attempts: 3,
          correct: 1,
        ),
        FeedbackConcept(
          conceptId: 'primary_key',
          name: LocalizedText(
              ar: 'المفتاح الأساسي (Primary Key)', en: 'Primary Key'),
          state: MasteryState.insufficientEvidence,
          attempts: 1,
          correct: 0,
        ),
      ],
      hints: const [
        FeedbackHint(
          conceptId: 'foreign_key',
          prerequisiteId: 'primary_key',
          signal: PrerequisiteSignal.needsMoreEvidence,
        ),
      ],
      recommendations: const [
        FeedbackRecommendation(
          conceptId: 'primary_key',
          reason: RecommendationReason.reviewPrerequisite,
          relatedConceptId: 'foreign_key',
          resources: [
            FeedbackResource(
              id: 'res_pk_video',
              title:
                  LocalizedText(ar: 'شرح المفتاح الأساسي', en: 'Primary keys'),
              type: ResourceType.video,
              url: 'https://example.com/pk',
            ),
          ],
        ),
      ],
      explanation: const FeedbackExplanation(
        text: LocalizedText(
          ar: 'قد يساعدك مراجعة المفتاح الأساسي أولاً.',
          en: 'Reviewing primary keys first may help.',
        ),
        source: ExplanationSource.template,
      ),
    );

void _contract(String name, Future<SessionRepository> Function() make) {
  group(name, () {
    late SessionRepository repo;
    late Session session;

    setUp(() async {
      repo = await make();
      session = await repo.createSession(
        courseId: 'database_systems',
        ownerId: 'teacher',
        questions: const [QuestionRef('db_pk_001', 1)],
      );
    });

    test('nothing before release; own feedback after', () async {
      final seen = <StudentFeedback?>[];
      final sub = repo.watchMyFeedback(session.id, 's1').listen(seen.add);
      await pumpEventQueue();
      expect(seen.last, isNull);

      await repo.saveFeedback(session.id, {
        's1': _feedback(Language.ar),
        's2': _feedback(Language.en),
      });
      await pumpEventQueue();
      expect(seen.last, isNull, reason: 'saved but not released yet');

      await repo.closeSession(session.id);
      await repo.releaseFeedback(session.id);
      await pumpEventQueue();
      final mine = seen.last!;
      expect(mine.language, Language.ar);
      expect(mine.concepts.first.name.ar, 'المفتاح الخارجي');
      expect(mine.concepts.first.state, MasteryState.possibleDifficulty);
      expect(mine.concepts.first.correct, 1);
      expect(mine.concepts.first.attempts, 3);
      expect(mine.recommendations.single.resources.single.url,
          'https://example.com/pk');
      expect(mine.explanation!.source, ExplanationSource.template);
      await sub.cancel();
    });

    test('a participant without feedback gets null after release', () async {
      await repo.saveFeedback(session.id, {'s1': _feedback(Language.ar)});
      await repo.releaseFeedback(session.id);
      expect(await repo.watchMyFeedback(session.id, 'nobody').first, isNull);
    });
  });
}

void main() {
  test('a resource keeps its description; older documents have none', () {
    final r = FeedbackResource.from(const Resource(
      id: 'r1',
      conceptIds: ['pk'],
      type: ResourceType.activity,
      language: ResourceLanguage.both,
      title: LocalizedText(ar: 'نشاط', en: 'Activity'),
      description: LocalizedText(ar: 'صمّم جدولين', en: 'Design two tables'),
    ));
    final back = FeedbackResource.fromJson(r.toJson());
    expect(back.description!.ar, 'صمّم جدولين');
    expect(back.url, isNull);
    final old = FeedbackResource.fromJson({
      'id': 'r2',
      'title': {'ar': 'فيديو', 'en': 'Video'},
      'type': 'video',
      'url': 'https://example.edu/v',
    });
    expect(old.description, isNull);
  });

  test('StudentFeedback survives a JSON round trip', () {
    final back = StudentFeedback.fromJson(_feedback(Language.en).toJson());
    expect(back.language, Language.en);
    expect(back.concepts[1].name.ar, 'المفتاح الأساسي (Primary Key)');
    expect(back.concepts[1].state, MasteryState.insufficientEvidence);
    expect(back.hints.single.signal, PrerequisiteSignal.needsMoreEvidence);
    expect(back.recommendations.single.reason,
        RecommendationReason.reviewPrerequisite);
    expect(back.recommendations.single.relatedConceptId, 'foreign_key');
    expect(
        back.recommendations.single.resources.single.type, ResourceType.video);
    expect(back.explanation!.text.en, 'Reviewing primary keys first may help.');
  });

  test('unknown values from an older or newer app do not crash', () {
    final back = StudentFeedback.fromJson({
      'language': 'fr',
      'concepts': [
        {
          'concept_id': 'x',
          'name': {'ar': 'س', 'en': 'X'},
          'state': 'new_state'
        },
      ],
      'explanation': {
        'text': {'ar': 'أ', 'en': 'a'},
        'source': 'robot'
      },
    });
    expect(back.language, Language.ar);
    expect(back.concepts.single.state, MasteryState.insufficientEvidence);
    expect(back.concepts.single.attempts, 0);
    expect(back.explanation!.source, ExplanationSource.template);
  });

  _contract(
      'InMemorySessionRepository', () async => InMemorySessionRepository());

  late FakeFirebaseFirestore db;
  _contract('FirestoreSessionRepository', () async {
    db = FakeFirebaseFirestore();
    return FirestoreSessionRepository(db, ensureParticipant: () async => 's1');
  });

  test('the Firestore document holds no answers, keys or IDs', () async {
    final db = FakeFirebaseFirestore();
    final repo =
        FirestoreSessionRepository(db, ensureParticipant: () async => 's1');
    final session = await repo.createSession(
      courseId: 'database_systems',
      ownerId: 'teacher',
      questions: const [],
    );
    await repo.saveFeedback(session.id, {'s1': _feedback(Language.ar)});
    final doc = await db.doc('sessions/${session.id}/feedback/s1').get();
    final text = doc.data().toString();
    expect(doc.data()!.containsKey('created_at'), isTrue);
    expect(text, isNot(contains('correct_option_id')));
    expect(text, isNot(contains('selected_option_id')));
    expect(text, isNot(contains('participant_id')));
  });
}
