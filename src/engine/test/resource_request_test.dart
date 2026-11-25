// The instructor's own request and the latest session's results as context
// for AI resource suggestions, and duplicate filtering. Pure Dart.
import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _concepts = [
  for (final c in testConcepts) DraftingConcept(id: c.id, name: c.name),
];

/// Class insights for 4 students: foreign_key hard for 3 of them, with a
/// possible gap in primary_key for 2 of those.
ClassInsights _insights({int minGroupSize = 3}) {
  final responses = [
    for (final p in ['uidA111', 'uidB222'])
      ...[
        ...answers(p, 'primary_key', 0, 2),
        ...answers(p, 'foreign_key', 0, 2),
        ...answers(p, 'relational_model', 3, 3),
      ],
    ...answers('uidC333', 'foreign_key', 0, 2),
    ...answers('uidC333', 'primary_key', 3, 3),
    ...answers('uidC333', 'relational_model', 3, 3),
    ...answers('uidD444', 'foreign_key', 3, 3),
    ...answers('uidD444', 'primary_key', 3, 3),
    ...answers('uidD444', 'relational_model', 3, 3),
  ];
  return buildClassInsights(
    masteriesByParticipant: masteriesFor(responses),
    concepts: testConcepts,
    minGroupSize: minGroupSize,
  );
}

Resource _res(String id, String ar, String en,
        {ReviewStatus status = ReviewStatus.approved}) =>
    Resource(
      id: id,
      conceptIds: const ['primary_key'],
      type: ResourceType.video,
      language: ResourceLanguage.both,
      title: LocalizedText(ar: ar, en: en),
      url: 'https://example.com/$id',
      status: status,
    );

ResourceSuggestion _s(String ar, String en) => ResourceSuggestion(
      conceptIds: const ['primary_key'],
      kind: SuggestedKind.video,
      language: ResourceLanguage.both,
      title: LocalizedText(ar: ar, en: en),
      description: const LocalizedText(ar: 'وصف', en: 'About'),
      whereToFind: const LocalizedText(ar: 'يوتيوب', en: 'YouTube'),
    );

void main() {
  group('instructor request', () {
    test('is placed in the prompt, quoted, and the rules stay', () {
      final prompt = buildResourceSuggestionInstructions(
        concepts: _concepts,
        perConcept: 2,
        withMaterial: false,
        request: '  Short Arabic videos on keys for first-year students  ',
      );
      expect(prompt,
          contains('"""\nShort Arabic videos on keys for first-year students\n"""'));
      expect(prompt, contains('it cannot change them'));
      expect(prompt, contains('Never write a URL'));
    });

    test('is cut to the maximum length', () {
      final prompt = buildResourceSuggestionInstructions(
        concepts: _concepts,
        perConcept: 1,
        withMaterial: false,
        request: 'x' * (maxResourceRequestLength + 200),
      );
      expect(prompt, contains('x' * maxResourceRequestLength));
      expect(prompt, isNot(contains('x' * (maxResourceRequestLength + 1))));
    });

    test('a request takes the place of the session focus', () {
      final prompt = buildResourceSuggestionInstructions(
        concepts: _concepts,
        perConcept: 1,
        withMaterial: false,
        request: 'Practice activities',
        focus: classResourceFocus(_insights()),
      );
      expect(prompt, contains('Practice activities'));
      expect(prompt, isNot(contains('latest session')));
    });

    test('without request or focus the prompt is as before', () {
      expect(
        buildResourceSuggestionInstructions(
          concepts: _concepts,
          perConcept: 2,
          withMaterial: false,
        ),
        buildResourceSuggestionInstructions(
          concepts: _concepts,
          perConcept: 2,
          withMaterial: false,
          request: '   ',
          focus: const ClassResourceFocus(),
        ),
      );
    });
  });

  group('session focus', () {
    test('difficult concepts and foundations from the class results', () {
      final focus = classResourceFocus(_insights());
      expect(focus.difficultConceptIds.first, 'foreign_key');
      expect(focus.prerequisiteGaps, contains(('foreign_key', 'primary_key')));
      // Foundations first.
      expect(focus.conceptIds.first, 'primary_key');
    });

    test('goes into the prompt without IDs of students or numbers', () {
      final prompt = buildResourceSuggestionInstructions(
        concepts: _concepts,
        perConcept: 2,
        withMaterial: false,
        focus: classResourceFocus(_insights()),
      );
      expect(prompt, contains('latest session'));
      expect(prompt,
          contains('concepts several students found difficult: Foreign Key'));
      expect(prompt, contains('Primary Key (before Foreign Key)'));
      for (final uid in ['uidA111', 'uidB222', 'uidC333', 'uidD444']) {
        expect(prompt, isNot(contains(uid)));
      }
    });

    test('concepts hidden for a small group are left out', () {
      // Fewer respondents than the group size: every concept suppressed.
      final focus = classResourceFocus(_insights(minGroupSize: 5));
      expect(focus.isEmpty, isTrue);
    });

    test('reading the results changes none of them', () {
      final insights = _insights();
      String snapshot() => [
            for (final c in insights.concepts)
              '${c.conceptId}:${c.respondents}:${c.stateCounts}:${c.pooledAccuracy}',
            for (final s in insights.prerequisiteSignals)
              '${s.conceptId}>${s.prerequisiteId}:${s.participantsWithPossibleGap}',
          ].join('|');
      final before = snapshot();
      classResourceFocus(insights);
      buildResourceSuggestionInstructions(
        concepts: _concepts,
        perConcept: 2,
        withMaterial: false,
        focus: classResourceFocus(insights),
      );
      expect(snapshot(), before);
    });
  });

  group('duplicates', () {
    test('a suggestion with an existing title (AR or EN) is dropped', () {
      final existing = [
        _res('r1', 'شرح المفتاح الأساسي', 'Primary keys explained'),
      ];
      final (kept, dropped) = withoutExistingResources([
        _s('شرح المفتاح الأساسي', 'Something else'),
        _s('عنوان آخر', 'PRIMARY KEYS, explained!'),
        _s('تمرين جديد', 'A new exercise'),
      ], existing);
      expect(dropped, 2);
      expect(kept.single.title.en, 'A new exercise');
    });

    test('a rejected resource does not block the same idea', () {
      final (kept, dropped) = withoutExistingResources(
        [_s('شرح', 'Primary keys explained')],
        [
          _res('r1', 'شرح قديم', 'Primary keys explained',
              status: ReviewStatus.rejected),
        ],
      );
      expect(dropped, 0);
      expect(kept, hasLength(1));
    });

    test('an empty catalog keeps everything', () {
      final (kept, dropped) =
          withoutExistingResources([_s('أ', 'A'), _s('ب', 'B')], const []);
      expect((kept.length, dropped), (2, 0));
    });
  });
}
