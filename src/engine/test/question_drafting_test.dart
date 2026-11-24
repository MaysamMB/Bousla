import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

const _known = {'primary_key', 'foreign_key'};

Map<String, Object?> _q({
  List<Object?> concepts = const ['primary_key'],
  Object? promptAr = 'ما الخاصية التي يجب أن يحققها المفتاح الأساسي (Primary Key)؟',
  Object? promptEn = 'Which property must a primary key have?',
  List<Object?>? options,
  Object? correct = 'x2',
  Object? location = 'page 4',
  Object? difficulty = 'basic',
}) => {
  'concept_ids': concepts,
  'prompt_ar': promptAr,
  'prompt_en': promptEn,
  'options':
      options ??
      [
        {'id': 'x1', 'text_ar': 'يقبل التكرار', 'text_en': 'Allows duplicates'},
        {
          'id': 'x2',
          'text_ar': 'فريد ولا يقبل NULL',
          'text_en': 'Unique and not NULL',
        },
        {'id': 'x3', 'text_ar': 'نصي دائماً', 'text_en': 'Always text'},
        {'id': 'x4', 'text_ar': 'اختياري', 'text_en': 'Optional'},
      ],
  'correct_option_id': correct,
  'source_location': location,
  'difficulty': difficulty,
};

DraftParseResult _parse(Object json, {int max = 10}) => parseQuestionDrafts(
  json is String ? json : jsonEncode(json),
  knownConceptIds: _known,
  maxCount: max,
);

void main() {
  group('parseQuestionDrafts', () {
    test('accepts a bilingual draft and renames options a, b, c, d', () {
      final r = _parse({
        'questions': [_q()],
      });
      expect(r.dropped, isEmpty);
      final q = r.accepted.single;
      expect([for (final o in q.options) o.id], ['a', 'b', 'c', 'd']);
      // The correct answer follows its option (was x2, now b).
      expect(q.correctOptionId, 'b');
      expect(q.options[1].text.en, 'Unique and not NULL');
      expect(q.prompt.ar, contains('(Primary Key)'));
      expect(q.sourceLocation, 'page 4');
      expect(q.difficulty, 'basic');
    });

    test('code in options is allowed in both languages', () {
      final r = _parse({
        'questions': [
          _q(
            options: [
              {'id': 'a', 'text_ar': 'student_id', 'text_en': 'student_id'},
              {'id': 'b', 'text_ar': 'name', 'text_en': 'name'},
            ],
            correct: 'a',
          ),
        ],
      });
      expect(r.accepted, hasLength(1));
    });

    test('drops drafts that fail the checks, one reason each', () {
      final r = _parse({
        'questions': [
          _q(concepts: ['made_up_concept']),
          _q(promptAr: 'Which property must a primary key have?'),
          _q(promptAr: ''),
          _q(promptEn: '  '),
          _q(correct: 'nope'),
          _q(
            options: [
              {'id': 'a', 'text_ar': 'نعم', 'text_en': 'Yes'},
            ],
            correct: 'a',
          ),
          _q(
            options: [
              {'id': 'a', 'text_ar': '', 'text_en': 'Yes'},
              {'id': 'b', 'text_ar': 'لا', 'text_en': 'No'},
            ],
            correct: 'a',
          ),
          _q(promptEn: null),
          'not an object',
        ],
      });
      expect(r.accepted, isEmpty);
      expect(r.dropped, [
        DraftIssue.unknownConcept,
        DraftIssue.promptArabicHasNoArabicLetters,
        DraftIssue.promptArabicMissing,
        DraftIssue.promptEnglishMissing,
        DraftIssue.correctOptionMissing,
        DraftIssue.tooFewOptions,
        DraftIssue.optionTextMissing,
        DraftIssue.malformed,
        DraftIssue.malformed,
      ]);
    });

    test('unknown concept IDs are removed; known ones are kept', () {
      final r = _parse({
        'questions': [
          _q(concepts: ['invented', 'foreign_key', 'foreign_key']),
        ],
      });
      expect(r.accepted.single.conceptIds, ['foreign_key']);
    });

    test('duplicate prompts are dropped', () {
      final r = _parse({
        'questions': [
          _q(),
          _q(promptEn: 'Which property must a PRIMARY KEY have ?'),
        ],
      });
      expect(r.accepted, hasLength(1));
      expect(r.dropped, [DraftIssue.duplicate]);
    });

    test('at most maxCount drafts are accepted', () {
      final r = _parse({
        'questions': [
          _q(),
          _q(promptEn: 'What does a foreign key reference?'),
          _q(promptEn: 'Why is a primary key unique?'),
        ],
      }, max: 2);
      expect(r.accepted, hasLength(2));
    });

    test('not JSON, or the wrong shape, is one invalidJson issue', () {
      expect(_parse('Sure! Here are your questions:').dropped, [
        DraftIssue.invalidJson,
      ]);
      expect(_parse({'items': []}).dropped, [DraftIssue.invalidJson]);
    });

    test('accepts JSON wrapped in a code fence, or a bare list', () {
      final fenced = '```json\n${jsonEncode({
        'questions': [_q()],
      })}\n```';
      expect(_parse(fenced).accepted, hasLength(1));
      expect(_parse([_q()]).accepted, hasLength(1));
    });

    test('an unknown difficulty and an empty location are left out', () {
      final q = _parse({
        'questions': [_q(difficulty: 'very hard', location: ' ')],
      }).accepted.single;
      expect(q.difficulty, isNull);
      expect(q.sourceLocation, isNull);
    });
  });

  group('buildQuestionDraftingInstructions', () {
    test('lists only the given concepts and asks for both languages', () {
      final text = buildQuestionDraftingInstructions(
        count: 5,
        concepts: const [
          DraftingConcept(
            id: 'primary_key',
            name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
          ),
        ],
      );
      expect(text, contains('- primary_key: Primary Key / المفتاح الأساسي'));
      expect(text, contains('up to 5'));
      expect(text, contains('BOTH Arabic'));
      expect(text, contains('reviews, edits or rejects'));
    });
  });

  test('the JSON schema requires the fields the parser needs', () {
    final schema = questionDraftingJsonSchema();
    final item =
        ((schema['properties'] as Map)['questions'] as Map)['items'] as Map;
    expect(
      item['required'],
      containsAll([
        'concept_ids',
        'prompt_ar',
        'prompt_en',
        'options',
        'correct_option_id',
      ]),
    );
  });
}
