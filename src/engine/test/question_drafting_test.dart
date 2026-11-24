import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

const _known = {'primary_key', 'foreign_key'};

Map<String, Object?> _q({
  List<Object?> concepts = const ['primary_key'],
  Object? promptAr =
      'ما الخاصية التي يجب أن يحققها المفتاح الأساسي (Primary Key)؟',
  Object? promptEn = 'Which property must a primary key have?',
  List<Object?>? options,
  Object? correct = 'x2',
  Object? location = 'page 4',
  Object? difficulty = 'basic',
}) =>
    {
      'concept_ids': concepts,
      'prompt_ar': promptAr,
      'prompt_en': promptEn,
      'options': options ??
          [
            {
              'id': 'x1',
              'text_ar': 'يقبل التكرار',
              'text_en': 'Allows duplicates'
            },
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
      // The correct answer follows its option (it was x2).
      final correct = q.options.singleWhere((o) => o.id == q.correctOptionId);
      expect(correct.text.en, 'Unique and not NULL');
      expect(correct.text.ar, 'فريد ولا يقبل NULL');
      expect(
        {for (final o in q.options) o.text.en},
        {'Allows duplicates', 'Unique and not NULL', 'Always text', 'Optional'},
      );
      expect(q.prompt.ar, contains('(Primary Key)'));
      expect(q.sourceLocation, 'page 4');
      expect(q.difficulty, 'basic');
    });

    test('the correct answer is not always first, and the order is stable', () {
      // Models tend to put the correct answer first.
      final drafts = [
        for (var i = 0; i < 12; i++)
          _q(promptEn: 'Question number $i about primary keys?', correct: 'x1'),
      ];
      final first = _parse({'questions': drafts}, max: 20).accepted;
      final positions = {for (final q in first) q.correctOptionId};
      expect(positions.length, greaterThan(1));
      final again = _parse({'questions': drafts}, max: 20).accepted;
      expect(
        [for (final q in again) q.correctOptionId],
        [for (final q in first) q.correctOptionId],
      );
    });

    test('options repeated in the question text are removed (live case)', () {
      // From a real Gemini answer on 24 Nov.
      const options = [
        (
          'تُعامل كعمليات منفصلة غير مرتبطة',
          'Treated as separate unrelated operations'
        ),
        ('تُعامل كوحدة وفق خصائص ACID', 'Treated as a unit following ACID'),
        (
          'تُحفظ دائماً كملف أرشيف منطقي',
          'Always saved as a logical archive file'
        ),
        (
          'تُنفذ فقط عند إيقاف تشغيل التطبيق',
          'Run only when the application stops'
        ),
      ];
      final r = _parse({
        'questions': [
          _q(
            promptAr:
                'كيف يتم التعامل مع مجموعة العمليات التي تشكل (Transaction) '
                'في نظام إدارة قواعد البيانات؟ أ) ${options[0].$1} '
                'ب) ${options[1].$1} ج) ${options[2].$1} د) ${options[3].$1}',
            promptEn:
                'How is a group of operations forming a transaction handled '
                'in a DBMS? a) ${options[0].$2} b) ${options[1].$2} '
                'c) ${options[2].$2} d) ${options[3].$2}',
            options: [
              for (var i = 0; i < 4; i++)
                {
                  'id': 'o$i',
                  'text_ar': options[i].$1,
                  'text_en': options[i].$2
                },
            ],
            correct: 'o1',
          ),
        ],
      });
      final q = r.accepted.single;
      expect(
        q.prompt.ar,
        'كيف يتم التعامل مع مجموعة العمليات التي تشكل (Transaction) '
        'في نظام إدارة قواعد البيانات؟',
      );
      expect(
        q.prompt.en,
        'How is a group of operations forming a transaction handled in a DBMS?',
      );
    });

    test('a question that is only the list of options is dropped', () {
      final r = _parse({
        'questions': [
          _q(
            promptAr: 'يقبل التكرار، فريد ولا يقبل NULL',
            promptEn: 'a) Allows duplicates b) Unique and not NULL',
          ),
        ],
      });
      expect(r.dropped, [DraftIssue.optionsInPrompt]);
    });

    test('one option word inside the question is left alone', () {
      final q = _parse({
        'questions': [
          _q(promptEn: 'Is "Optional" a valid property of a primary key?'),
        ],
      }).accepted.single;
      expect(q.prompt.en, 'Is "Optional" a valid property of a primary key?');
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
      expect(text, contains('Write 5 multiple-choice questions'));
      expect(text, contains('Several questions may cover the same concept'));
      expect(text, contains('BOTH Arabic'));
      expect(text, contains('reviews, edits or rejects'));
      expect(text, contains('Vary the position of the correct answer'));
      expect(text, contains('must not list the options'));
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
