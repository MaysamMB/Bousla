// Teacher-managed resources, additions to the instructor's resource
// workflow: duplicate links refused, the latest session's class results as
// context for AI suggestions, and the engine's results left unchanged.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/sample_content.dart';
import 'package:bousla_app/data/feedback_publisher.dart';
import 'package:bousla_app/data/firebase/firestore_content_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:bousla_app/data/repositories/content_repository.dart';
import 'package:bousla_app/data/resource_review.dart';
import 'package:bousla_app/features/instructor/resources/session_focus.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

ResourceDraft _draft(String url, {String? id, String title = 'فيديو'}) =>
    ResourceDraft(
      id: id,
      conceptIds: const ['primary_key'],
      type: ResourceType.video,
      language: ResourceLanguage.ar,
      titleText: title,
      url: url,
    );

Resource _existing(String url, {ReviewStatus status = ReviewStatus.approved}) =>
    Resource(
      id: 'r1',
      conceptIds: const ['primary_key'],
      type: ResourceType.video,
      language: ResourceLanguage.en,
      title: const LocalizedText(ar: 'أ', en: 'A'),
      url: url,
      status: status,
    );

Future<FirestoreContentRepository> _firestore() async {
  final db = FakeFirebaseFirestore();
  final course = db.collection('courses').doc(_course);
  await course.set({'name': sampleCourse['name'], 'owner_id': 'teacher'});
  for (final c in sampleConcepts) {
    await course.collection('concepts').doc(c['id'] as String).set(c);
  }
  return FirestoreContentRepository(db, currentUserId: () => 'teacher');
}

/// A session of the in-memory course where [wrong] students answer every
/// foreign key question wrongly and one answers everything right.
Future<(AppServices, Session)> _sessionWithAnswers({int wrong = 3}) async {
  final services = AppServices.inMemory();
  final questions = await services.content.listQuestions(_course);
  final keys = await services.content.answerKeys(_course);
  final session = await services.sessions.createSession(
    courseId: _course,
    ownerId: InMemoryAuthService.devInstructorId,
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  String keyOf(QuestionView q) =>
      keys.firstWhere((k) => k.questionId == q.id).correctOptionId;
  for (var s = 0; s <= wrong; s++) {
    final good = s == wrong;
    for (final q in questions) {
      final right = keyOf(q);
      final pick = good || !q.conceptIds.contains('foreign_key')
          ? right
          : q.options.firstWhere((o) => o.id != right).id;
      await services.sessions.submitResponse(
        session.id,
        Response(
          participantId: 'student$s',
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId: pick,
          displayLanguage: Language.ar,
        ),
      );
    }
  }
  return (services, session);
}

void main() {
  group('duplicate links', () {
    final approved = {'primary_key'};

    test('the same page is refused, however the link is written', () {
      for (final url in [
        'https://example.edu/pk',
        'http://example.edu/pk',
        'https://www.example.edu/pk/',
        'https://EXAMPLE.edu/pk',
      ]) {
        expect(
          validateResourceDraft(
            _draft(url),
            approved,
            existing: [_existing('https://example.edu/pk')],
          ),
          [ResourceDraftIssue.duplicateLink],
          reason: url,
        );
      }
    });

    test('another page, the same resource being edited, or a rejected one '
        'are fine', () {
      expect(
        validateResourceDraft(_draft('https://example.edu/fk'), approved,
            existing: [_existing('https://example.edu/pk')]),
        isEmpty,
      );
      expect(
        validateResourceDraft(_draft('https://example.edu/pk', id: 'r1'),
            approved,
            existing: [_existing('https://example.edu/pk')]),
        isEmpty,
      );
      expect(
        validateResourceDraft(_draft('https://example.edu/pk'), approved,
            existing: [
              _existing('https://example.edu/pk',
                  status: ReviewStatus.rejected),
            ]),
        isEmpty,
      );
    });

    test('unsafe or malformed links are still refused first', () {
      for (final url in ['javascript:alert(1)', 'ftp://example.edu/x', 'pk']) {
        expect(
          validateResourceDraft(_draft(url), approved,
              existing: [_existing(url)]),
          [ResourceDraftIssue.urlInvalid],
          reason: url,
        );
      }
    });

    for (final (name, make) in [
      ('in memory', () async => InMemoryContentRepository() as ContentRepository),
      ('Firestore', () async => await _firestore() as ContentRepository),
    ]) {
      test('$name: a second resource with the same link is not saved',
          () async {
        final repo = await make();
        await repo.saveResource(_course, _draft('https://example.edu/pk-dup'));
        await expectLater(
          repo.saveResource(
            _course,
            _draft('https://www.example.edu/pk-dup/', title: 'نسخة'),
          ),
          throwsA(
            isA<InvalidResourceException>().having(
              (e) => e.issues,
              'issues',
              [ResourceDraftIssue.duplicateLink],
            ),
          ),
        );
        final all = await repo.listResources(_course, approvedOnly: false);
        expect(
          all.where((r) => r.url?.contains('pk-dup') ?? false),
          hasLength(1),
        );
      });
    }
  });

  group('latest session as context', () {
    test('no session yet: no focus', () async {
      expect(
        await loadLatestSessionFocus(AppServices.inMemory(), _course),
        isNull,
      );
    });

    test('a session without answers: no focus', () async {
      final services = AppServices.inMemory();
      await services.sessions.createSession(
        courseId: _course,
        ownerId: InMemoryAuthService.devInstructorId,
        questions: const [QuestionRef('db_pk_001', 1)],
      );
      expect(await loadLatestSessionFocus(services, _course), isNull);
    });

    test('the concepts the class found difficult, from the engine', () async {
      final (services, session) = await _sessionWithAnswers();
      final f = await loadLatestSessionFocus(services, _course);
      expect(f, isNotNull);
      expect(f!.session.id, session.id);
      expect(f.focus.difficultConceptIds, contains('foreign_key'));
      expect(f.focus.difficultConceptIds, isNot(contains('primary_key')));
    });

    test('too few students: nothing per concept (privacy), so no focus',
        () async {
      // 2 students: under the 3-student minimum of the class insights.
      final (services, _) = await _sessionWithAnswers(wrong: 1);
      final f = await loadLatestSessionFocus(services, _course);
      expect(f?.focus.isEmpty ?? true, isTrue);
    });
  });

  test('AI suggestions change no engine result and no student feedback',
      () async {
    final (services, session) = await _sessionWithAnswers();
    final content = services.content;
    final responses = await services.sessions.watchResponses(session.id).first;
    Future<String> feedbackNow() async {
      final questions =
          await content.questionsForSession(_course, session.questions);
      final computed = computeFeedback(
        responses: responses,
        questions: [for (final q in questions) q.question],
        keys: await content.answerKeys(_course),
        concepts: await content.listConcepts(_course),
        resources: await content.listResources(_course),
      );
      return [
        for (final e in computed.entries)
          '${e.key}:${e.value.feedback.toJson()}',
      ].join('\n');
    }

    final before = await feedbackNow();
    await content.saveAiResourceSuggestions(
      _course,
      modelName: 'fake',
      suggestions: const [
        ResourceSuggestion(
          conceptIds: ['foreign_key'],
          kind: SuggestedKind.video,
          language: ResourceLanguage.both,
          title: LocalizedText(ar: 'فيديو جديد', en: 'New video'),
          description: LocalizedText(ar: 'وصف', en: 'About'),
          whereToFind: LocalizedText(ar: 'يوتيوب', en: 'YouTube'),
        ),
      ],
    );
    await loadLatestSessionFocus(services, _course);
    // Pending AI suggestions never reach students; states, evidence and
    // recommendations are the same.
    expect(await feedbackNow(), before);
  });
}
