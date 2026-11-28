import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

const _pk = DraftingConcept(
    id: 'primary_key',
    name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'));
const _fk = DraftingConcept(
    id: 'foreign_key',
    name: LocalizedText(ar: 'المفتاح الخارجي', en: 'Foreign Key'));

Map<String, Object?> _q(String concept, String en, {String correct = 'a'}) => {
      'concept_ids': [concept],
      'prompt_ar': 'سؤال عن $en',
      'prompt_en': 'A question about $en?',
      'options': [
        for (final o in ['a', 'b', 'c', 'd'])
          {'id': o, 'text_ar': 'خيار $o $en', 'text_en': 'Option $o $en'},
      ],
      'correct_option_id': correct,
      'source_location': 'practice',
    };

void main() {
  test('the instructions name only the concepts, and the count', () {
    final text = buildPracticeQuizInstructions(concepts: [_pk, _fk]);
    expect(text, contains('- primary_key: Primary Key / المفتاح الأساسي'));
    expect(text, contains('Write 4 multiple-choice questions: 2 for each'));
    expect(text, contains('BOTH Arabic'));
  });

  test('guards drop bad questions; at most two per reviewed concept', () {
    final answer = jsonEncode({
      'questions': [
        _q('primary_key', 'keys 1'),
        _q('primary_key', 'keys 2'),
        _q('primary_key', 'keys 3'),
        _q('foreign_key', 'refs 1'),
        _q('normalization', 'other'), // not asked for: dropped
        {..._q('foreign_key', 'refs 2'), 'correct_option_id': 'z'}, // no key
      ],
    });
    final parsed = parseQuestionDrafts(answer,
        knownConceptIds: {'primary_key', 'foreign_key'}, maxCount: 10);
    expect(
        parsed.dropped,
        containsAll([
          DraftIssue.unknownConcept,
          DraftIssue.correctOptionMissing,
        ]));
    final chosen = selectPracticeQuestions(parsed,
        conceptIds: ['primary_key', 'foreign_key']);
    expect(chosen.map((q) => q.prompt.en), [
      'A question about keys 1?',
      'A question about keys 2?',
      'A question about refs 1?',
    ]);
    // Every kept question has exactly one correct option among its own.
    for (final q in chosen) {
      expect(q.options.map((o) => o.id), contains(q.correctOptionId));
    }
  });
}
