import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

const _known = {'pk', 'fk'};

Map<String, Object?> _entry({
  List<String> concepts = const ['pk'],
  String kind = 'video',
  String titleAr = 'شرح المفتاح الأساسي',
  String titleEn = 'Primary key explained',
  String whereEn = 'YouTube, an introductory course from a university channel',
  String query = 'primary key database tutorial',
  String? location,
}) =>
    {
      'concept_ids': concepts,
      'kind': kind,
      'language': 'en',
      'title_ar': titleAr,
      'title_en': titleEn,
      'description_ar': 'فيديو قصير يشرح لماذا يجب أن يكون المفتاح الأساسي فريداً.',
      'description_en': 'A short video on why a primary key must be unique.',
      'where_to_find_ar': 'يوتيوب، مساق تمهيدي من قناة جامعية',
      'where_to_find_en': whereEn,
      'search_query': query,
      if (location != null) 'source_location': location,
    };

SuggestionParseResult _parse(List<Map<String, Object?>> entries,
        {bool material = false, int max = 10}) =>
    parseResourceSuggestions(
      jsonEncode({'resources': entries}),
      knownConceptIds: _known,
      maxCount: max,
      allowMaterial: material,
    );

void main() {
  test('a good suggestion is kept, with no URL', () {
    final r = _parse([_entry()]);
    expect(r.dropped, isEmpty);
    final s = r.accepted.single;
    expect(s.kind, SuggestedKind.video);
    expect(s.kind.resourceType, ResourceType.video);
    expect(s.searchQuery, 'primary key database tutorial');
    expect(s.whereToFind.en, contains('YouTube'));
  });

  test('links anywhere are dropped (models invent URLs)', () {
    final r = _parse([
      _entry(whereEn: 'https://www.youtube.com/watch?v=abc'),
      _entry(titleEn: 'See w3schools.com/sql', titleAr: 'راجع الموقع'),
      _entry(query: 'www.example.org primary key'),
    ]);
    expect(r.accepted, isEmpty);
    expect(r.dropped, everyElement(SuggestionIssue.containsLink));
    // A site named without a domain is fine.
    expect(containsLink('Khan Academy or YouTube'), isFalse);
    expect(containsLink('موقع W3Schools'), isFalse);
  });

  test('unknown concepts, kinds and missing Arabic are dropped', () {
    final r = _parse([
      _entry(concepts: ['indexes']),
      _entry(kind: 'podcast'),
      _entry(kind: 'material'),
      _entry(titleAr: 'Primary key'),
    ]);
    expect(r.accepted, isEmpty);
    expect(r.dropped, [
      SuggestionIssue.unknownConcept,
      SuggestionIssue.unknownKind,
      SuggestionIssue.unknownKind,
      SuggestionIssue.arabicMissing,
    ]);
  });

  test('material only with a file; activities get no search words', () {
    final r = _parse([
      _entry(kind: 'material', location: 'page 12', titleEn: 'Lecture'),
      _entry(kind: 'activity', titleEn: 'Design two tables'),
    ], material: true);
    expect(r.dropped, isEmpty);
    expect(r.accepted[0].kind.resourceType, ResourceType.file);
    expect(r.accepted[0].sourceLocation, 'page 12');
    expect(r.accepted[0].searchQuery, isNull);
    expect(r.accepted[1].searchQuery, isNull);
  });

  test('duplicates, the limit and broken JSON', () {
    final r = _parse([_entry(), _entry(), _entry(titleEn: 'Other')], max: 2);
    expect(r.accepted, hasLength(2));
    expect(r.dropped, [SuggestionIssue.duplicate]);
    expect(
      parseResourceSuggestions('not json', knownConceptIds: _known, maxCount: 3)
          .dropped,
      [SuggestionIssue.invalidJson],
    );
  });

  test('the instructions forbid links and name the concepts', () {
    final text = buildResourceSuggestionInstructions(
      concepts: const [
        DraftingConcept(
          id: 'pk',
          name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary key'),
        ),
      ],
      perConcept: 2,
      withMaterial: false,
    );
    expect(text, contains('pk: Primary key / المفتاح الأساسي'));
    expect(text, contains('Never write a URL'));
    expect(text, isNot(contains('material:')));
  });

  test('Resource reads description and the AI brief from JSON', () {
    final r = Resource.fromJson({
      'id': 'r1',
      'concept_ids': ['pk'],
      'type': 'video',
      'language': 'en',
      'title': {'ar': 'شرح', 'en': 'Explained'},
      'description': {'ar': 'وصف', 'en': 'About'},
      'where_to_find': {'ar': 'يوتيوب', 'en': 'YouTube'},
      'search_query': 'primary key',
      'url': null,
      'provenance': {
        'source': 'ai_draft',
        'status': 'pending_review',
        'source_location': 'page 3',
      },
    });
    expect(r.status, ReviewStatus.pendingReview);
    expect(r.source, 'ai_draft');
    expect(r.description!.en, 'About');
    expect(r.whereToFind!.ar, 'يوتيوب');
    expect(r.searchQuery, 'primary key');
    expect(r.sourceLocation, 'page 3');
  });
}
