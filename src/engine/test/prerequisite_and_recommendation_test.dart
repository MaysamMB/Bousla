import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('analyzePrerequisites', () {
    List<PrerequisiteFinding> findingsFor(List<Response> rs) =>
        analyzePrerequisites(
            masteries: masteriesFor(rs)['p1']!, concepts: testConcepts);

    test('no difficulty → no findings', () {
      expect(findingsFor([...answers('p1', 'foreign_key', 4, 4)]), isEmpty);
    });

    test('prerequisite also struggling → possible contributing gap', () {
      final f = findingsFor([
        ...answers('p1', 'foreign_key', 0, 3),
        ...answers('p1', 'primary_key', 0, 2),
      ]);
      expect(f.where((x) => x.conceptId == 'foreign_key').single.signal,
          equals(PrerequisiteSignal.possibleContributingGap));
    });

    test('prerequisite not assessed → needs more evidence, not a conclusion',
        () {
      final f = findingsFor(answers('p1', 'foreign_key', 0, 3));
      expect(f.single.prerequisiteId, equals('primary_key'));
      expect(f.single.signal, equals(PrerequisiteSignal.needsMoreEvidence));
    });

    test('prerequisite with demonstrated mastery → unlikely cause', () {
      final f = findingsFor([
        ...answers('p1', 'foreign_key', 0, 3),
        ...answers('p1', 'primary_key', 3, 3),
      ]);
      expect(f.single.signal, equals(PrerequisiteSignal.unlikelyCause));
    });

    test('prerequisite emerging → uncertain', () {
      final f = findingsFor([
        ...answers('p1', 'foreign_key', 0, 3),
        ...answers('p1', 'primary_key', 2, 3),
      ]);
      expect(f.single.signal, equals(PrerequisiteSignal.uncertain));
    });

    test('concept without prerequisites gives no findings', () {
      expect(findingsFor(answers('p1', 'relational_model', 0, 3)), isEmpty);
    });

    test('only direct prerequisites are examined', () {
      final f = findingsFor([
        ...answers('p1', 'foreign_key', 0, 3),
        ...answers('p1', 'relational_model', 0, 3),
      ]);
      expect(
          f
              .where((x) => x.conceptId == 'foreign_key')
              .map((x) => x.prerequisiteId)
              .toList(),
          equals(['primary_key']));
    });
  });

  group('recommend', () {
    final resources = [
      Resource(
          id: 'pk_ar',
          conceptIds: ['primary_key'],
          type: ResourceType.video,
          language: ResourceLanguage.ar,
          title: t('فيديو', 'Video'),
          url: 'https://example.org/ar'),
      Resource(
          id: 'pk_en',
          conceptIds: ['primary_key'],
          type: ResourceType.link,
          language: ResourceLanguage.en,
          title: t('رابط', 'Link'),
          url: 'https://example.org/en'),
      Resource(
          id: 'pk_both',
          conceptIds: ['primary_key'],
          type: ResourceType.activity,
          language: ResourceLanguage.both,
          title: t('نشاط', 'Activity')),
      Resource(
          id: 'pk_draft',
          conceptIds: ['primary_key'],
          type: ResourceType.activity,
          language: ResourceLanguage.ar,
          title: t('مسودة', 'Draft'),
          status: ReviewStatus.pendingReview),
      Resource(
          id: 'fk_both',
          conceptIds: ['foreign_key'],
          type: ResourceType.activity,
          language: ResourceLanguage.both,
          title: t('نشاط', 'Activity')),
    ];

    List<Recommendation> recs(List<Response> rs, Language lang,
            {int max = 3}) =>
        recommend(
          masteries: masteriesFor(rs)['p1']!,
          concepts: testConcepts,
          resources: resources,
          preferredLanguage: lang,
          maxRecommendations: max,
        );

    final gapCase = [
      ...answers('p1', 'foreign_key', 0, 3),
      ...answers('p1', 'primary_key', 0, 2)
    ];

    test('foundations first: prerequisite gap before the struggling concept',
        () {
      final r = recs(gapCase, Language.ar);
      expect(r[0].conceptId, equals('primary_key'));
      expect(r[0].reason, equals(RecommendationReason.reviewPrerequisite));
      expect(r[0].relatedConceptId, equals('foreign_key'));
      expect(r[1].conceptId, equals('foreign_key'));
      expect(r[1].reason, equals(RecommendationReason.reviewConcept));
    });

    test('each concept appears once even if it is both a gap and a difficulty',
        () {
      final ids = recs(gapCase, Language.ar).map((r) => r.conceptId).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('Arabic speaker gets the Arabic resource first, then bilingual', () {
      expect(recs(gapCase, Language.ar)[0].resources.map((r) => r.id).toList(),
          equals(['pk_ar', 'pk_both']));
    });

    test('English speaker gets the English resource first, then bilingual', () {
      expect(recs(gapCase, Language.en)[0].resources.map((r) => r.id).toList(),
          equals(['pk_en', 'pk_both']));
    });

    test('resources not approved are never recommended', () {
      final all = recommend(
        masteries: masteriesFor(gapCase)['p1']!,
        concepts: testConcepts,
        resources: resources,
        preferredLanguage: Language.ar,
        maxResourcesEach: 10,
      ).expand((r) => r.resources).map((r) => r.id);
      expect(all.contains('pk_draft'), isFalse);
    });

    test('unassessed prerequisite → assess more, with no resources', () {
      final r = recs(answers('p1', 'foreign_key', 0, 3), Language.ar);
      final assess =
          r.where((x) => x.reason == RecommendationReason.assessMore).single;
      expect(assess.conceptId, equals('primary_key'));
      expect(assess.resources, isEmpty);
    });

    test('emerging concept → practice', () {
      final r = recs(answers('p1', 'primary_key', 2, 3), Language.ar);
      expect(r.single.reason, equals(RecommendationReason.practice));
    });

    test(
        'emerging only because of too few answers (2 of 2 correct) → no practice',
        () {
      expect(recs(answers('p1', 'primary_key', 2, 2), Language.ar), isEmpty);
    });

    test('everything mastered → no recommendations', () {
      expect(
          recs([...answers('p1', 'primary_key', 4, 4)], Language.ar), isEmpty);
    });

    test('respects the maximum number of recommendations', () {
      expect(recs(gapCase, Language.ar, max: 1), hasLength(1));
    });
  });
}
