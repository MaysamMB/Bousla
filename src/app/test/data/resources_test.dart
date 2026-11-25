// Instructor resources: added by hand (approved at once) or described by AI
// (pending, no link until the instructor adds one). Same rules in the
// in-memory and the Firestore repositories.
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/sample_content.dart';
import 'package:bousla_app/data/firebase/firestore_content_repository.dart';
import 'package:bousla_app/data/repositories/content_repository.dart';
import 'package:bousla_app/data/resource_review.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

const _suggestion = ResourceSuggestion(
  conceptIds: ['primary_key'],
  kind: SuggestedKind.video,
  language: ResourceLanguage.en,
  title: LocalizedText(ar: 'شرح المفتاح الأساسي', en: 'Primary key explained'),
  description: LocalizedText(ar: 'لماذا يكون فريداً', en: 'Why it is unique'),
  whereToFind: LocalizedText(ar: 'يوتيوب', en: 'YouTube'),
  searchQuery: 'primary key tutorial',
);

ResourceDraft _draft({
  String? id,
  String title = 'شرح المفتاح الأساسي',
  String? url = 'https://example.edu/pk',
  ResourceType type = ResourceType.video,
  List<String> concepts = const ['primary_key'],
  LocalizedText? keepTitle,
}) =>
    ResourceDraft(
      id: id,
      conceptIds: concepts,
      type: type,
      language: guessResourceLanguage(title),
      titleText: title,
      url: url,
      keepTitle: keepTitle,
    );

Future<FirestoreContentRepository> _firestore() async {
  final db = FakeFirebaseFirestore();
  final course = db.collection('courses').doc(_course);
  await course.set({'name': sampleCourse['name'], 'owner_id': 'teacher'});
  for (final c in sampleConcepts) {
    await course.collection('concepts').doc(c['id'] as String).set(c);
  }
  for (final r in sampleResources) {
    await course.collection('resources').doc(r['id'] as String).set(r);
  }
  return FirestoreContentRepository(db, currentUserId: () => 'teacher');
}

void main() {
  group('validateResourceDraft', () {
    const approved = {'primary_key'};
    test('a video needs a web link; an activity may have none', () {
      expect(validateResourceDraft(_draft(), approved), isEmpty);
      expect(validateResourceDraft(_draft(url: ''), approved),
          [ResourceDraftIssue.urlMissing]);
      expect(validateResourceDraft(_draft(url: 'youtube'), approved),
          [ResourceDraftIssue.urlInvalid]);
      expect(validateResourceDraft(_draft(url: 'javascript:alert(1)'), approved),
          [ResourceDraftIssue.urlInvalid]);
      expect(
        validateResourceDraft(
            _draft(url: null, type: ResourceType.activity), approved),
        isEmpty,
      );
    });

    test('a title and an approved concept are required', () {
      expect(
        validateResourceDraft(_draft(title: ' ', concepts: ['x']), approved),
        [ResourceDraftIssue.noConcept, ResourceDraftIssue.titleMissing],
      );
    });

    test('one title in any language; the language is guessed', () {
      expect(_draft(title: 'Keys video').title.en, 'Keys video');
      expect(_draft(title: 'Keys video').title.ar, 'Keys video');
      expect(guessResourceLanguage('Keys'), ResourceLanguage.en);
      expect(guessResourceLanguage('المفاتيح'), ResourceLanguage.ar);
    });
  });

  for (final (name, make) in [
    ('in memory', () async => InMemoryContentRepository() as ContentRepository),
    ('Firestore', () async => await _firestore() as ContentRepository),
  ]) {
    group('$name repository', () {
      test('an added resource is approved and recommended to students',
          () async {
        final repo = await make();
        final saved = await repo.saveResource(_course, _draft());
        expect(saved.status, ReviewStatus.approved);
        expect(saved.source, 'instructor');
        final approved = await repo.listResources(_course);
        expect(approved.map((r) => r.id), contains(saved.id));
        final read = approved.firstWhere((r) => r.id == saved.id);
        expect(read.url, 'https://example.edu/pk');
        expect(read.language, ResourceLanguage.ar);

        // The engine picks it for a student who needs primary keys.
        final recs = recommend(
          masteries: {
            'primary_key': const ConceptMastery(
              evidence: ConceptEvidence(
                conceptId: 'primary_key',
                attempts: 3,
                correct: 0,
              ),
              state: MasteryState.possibleDifficulty,
            ),
          },
          concepts: await repo.listConcepts(_course),
          resources: approved,
          preferredLanguage: Language.ar,
          maxResourcesEach: 10,
        );
        expect(
          recs.expand((r) => r.resources).map((r) => r.id),
          contains(saved.id),
        );
      });

      test('a bad draft is refused and nothing is saved', () async {
        final repo = await make();
        final before = (await repo.listResources(_course, approvedOnly: false))
            .length;
        await expectLater(
          repo.saveResource(_course, _draft(url: '')),
          throwsA(isA<InvalidResourceException>()),
        );
        expect((await repo.listResources(_course, approvedOnly: false)).length,
            before);
      });

      test('AI suggestions wait without a link, students never get them',
          () async {
        final repo = await make();
        final saved = await repo.saveAiResourceSuggestions(
          _course,
          modelName: 'test-model',
          suggestions: const [_suggestion],
        );
        final id = saved.single.id;
        final all = await repo.listResources(_course, approvedOnly: false);
        final pending = all.firstWhere((r) => r.id == id);
        expect(pending.status, ReviewStatus.pendingReview);
        expect(pending.url, isNull);
        expect(pending.source, 'ai_draft');
        expect(pending.searchQuery, 'primary key tutorial');
        expect(pending.whereToFind!.en, 'YouTube');
        expect((await repo.listResources(_course)).map((r) => r.id),
            isNot(contains(id)));

        // The instructor adds the link; the unchanged title keeps both
        // languages, and the AI description stays.
        final done = await repo.saveResource(
          _course,
          _draft(id: id, keepTitle: _suggestion.title),
        );
        expect(done.status, ReviewStatus.approved);
        final read =
            (await repo.listResources(_course)).firstWhere((r) => r.id == id);
        expect(read.title.en, 'Primary key explained');
        expect(read.title.ar, 'شرح المفتاح الأساسي');
        expect(read.description!.en, 'Why it is unique');
        expect(read.source, 'ai_draft');
        expect(read.url, 'https://example.edu/pk');
      });

      test('reject and restore', () async {
        final repo = await make();
        final saved = await repo.saveResource(_course, _draft());
        await repo.setResourcesStatus(
            _course, [saved.id, 'unknown'], ReviewStatus.rejected);
        expect((await repo.listResources(_course)).map((r) => r.id),
            isNot(contains(saved.id)));
        await repo.setResourcesStatus(
            _course, [saved.id], ReviewStatus.approved);
        expect((await repo.listResources(_course)).map((r) => r.id),
            contains(saved.id));
      });
    });
  }
}
