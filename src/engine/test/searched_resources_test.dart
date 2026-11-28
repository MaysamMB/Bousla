import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> _entry({
  String kind = 'video',
  String url = 'https://www.youtube.com/watch?v=abc',
  int minutes = 6,
  List<String> concepts = const ['primary_key'],
  String titleEn = 'Primary keys in 6 minutes',
}) =>
    {
      'concept_ids': concepts,
      'kind': kind,
      'language': 'en',
      'url': url,
      'minutes': minutes,
      'title_ar': 'المفتاح الأساسي في 6 دقائق',
      'title_en': titleEn,
      'description_ar': 'شرح قصير للمفتاح الأساسي مع مثال.',
      'description_en': 'A short explanation with an example.',
      'where_to_find_ar': 'يوتيوب',
      'where_to_find_en': 'YouTube',
    };

SuggestionParseResult _parse(List<Map<String, Object?>> entries,
        {Set<String> domains = const {'youtube.com', 'postgresql.org'}}) =>
    parseSearchedResourceSuggestions(
      'Here is what I found:\n${jsonEncode({'resources': entries})}\nDone.',
      knownConceptIds: {'primary_key', 'foreign_key'},
      maxCount: 10,
      searchedDomains: domains,
    );

void main() {
  test('keeps a link whose site the search returned', () {
    final r = _parse([_entry()]);
    expect(r.dropped, isEmpty);
    expect(r.accepted.single.url, 'https://www.youtube.com/watch?v=abc');
    expect(r.accepted.single.minutes, 6);
    expect(r.accepted.single.kind, SuggestedKind.video);
  });

  test('drops a link to a site the search did not return', () {
    final r = _parse([_entry(url: 'https://made-up-tutorials.example/pk')]);
    expect(r.accepted, isEmpty);
    expect(r.dropped, [SuggestionIssue.ungroundedLink]);
  });

  test('no searched sites: every linked suggestion is dropped', () {
    final r = _parse([_entry()], domains: const {});
    expect(r.accepted, isEmpty);
    expect(r.dropped, [SuggestionIssue.ungroundedLink]);
  });

  test('subdomains and youtu.be count; other schemes do not', () {
    final r = _parse([
      _entry(url: 'https://youtu.be/xyz', titleEn: 'A'),
      _entry(
          kind: 'article',
          url: 'https://www.postgresql.org/docs/current/ddl-constraints.html',
          titleEn: 'B'),
      _entry(url: 'javascript:alert(1)', titleEn: 'C'),
    ]);
    expect(r.accepted.map((s) => s.title.en), ['A', 'B']);
    expect(r.dropped, [SuggestionIssue.ungroundedLink]);
  });

  test('a long video is dropped; an activity needs no link', () {
    final r = _parse([
      _entry(minutes: 45, titleEn: 'Full course'),
      _entry(kind: 'activity', url: '', minutes: 0, titleEn: 'Mark the keys'),
    ]);
    expect(r.dropped, [SuggestionIssue.videoTooLong]);
    expect(r.accepted.single.kind, SuggestedKind.activity);
    expect(r.accepted.single.url, isNull);
  });

  test('links are still not allowed inside the text fields', () {
    final e = _entry()..['description_en'] = 'See www.example.com for more.';
    expect(_parse([e]).dropped, [SuggestionIssue.containsLink]);
  });

  test('the same link twice is kept once', () {
    final r = _parse([_entry(titleEn: 'A'), _entry(titleEn: 'B')]);
    expect(r.accepted, hasLength(1));
    expect(r.dropped, [SuggestionIssue.duplicate]);
  });

  test(
      'instructions use the questions, never answers, and ask for short videos',
      () {
    final text = buildSearchedResourceInstructions(
      concepts: [
        DraftingConcept(
          id: 'primary_key',
          name: const LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary key'),
        ),
      ],
      perConcept: 2,
      questionsByConcept: {
        'primary_key': ['Which column can be the primary key of Students?'],
      },
    );
    expect(text, contains('Which column can be the primary key of Students?'));
    expect(text, contains('Google Search'));
    expect(text, contains('at most $maxVideoMinutes minutes'));
    expect(text, contains('do not reveal or discuss answers'));
  });

  test('an optional instructor request is included', () {
    final text = buildSearchedResourceInstructions(
      concepts: [
        DraftingConcept(
          id: 'primary_key',
          name: const LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary key'),
        ),
      ],
      perConcept: 1,
      request: 'Arabic videos for beginners',
    );
    expect(text, contains('Arabic videos for beginners'));
  });
}
