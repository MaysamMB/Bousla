import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('scoreResponses', () {
    ScoringResult score(List<Response> rs) =>
        scoreResponses(responses: rs, questions: testQuestions, keys: testKeys);

    test('empty input gives empty result', () {
      final r = score([]);
      expect(r.scored, isEmpty);
      expect(r.ignored, isEmpty);
    });

    test('compares option IDs with the key', () {
      final r = score([
        answer('p1', 'primary_key_1', true),
        answer('p1', 'primary_key_2', false)
      ]);
      expect(r.scored.map((s) => s.isCorrect).toList(), equals([true, false]));
    });

    test('same choices give identical results in Arabic and English', () {
      final ar = score([
        answer('p1', 'primary_key_1', true, lang: Language.ar),
        answer('p1', 'primary_key_2', false, lang: Language.ar),
      ]);
      final en = score([
        answer('p1', 'primary_key_1', true, lang: Language.en),
        answer('p1', 'primary_key_2', false, lang: Language.en),
      ]);
      expect(en.scored.map((s) => s.isCorrect).toList(),
          equals(ar.scored.map((s) => s.isCorrect).toList()));
    });

    test('unknown question ID is reported, not dropped', () {
      final r = score([answer('p1', 'nope_1', true)]);
      expect(r.scored, isEmpty);
      expect(r.ignored.single.reason, equals(IgnoredReason.unknownQuestion));
    });

    test('answer for an unknown question version is reported', () {
      final r = score([answer('p1', 'primary_key_1', true, version: 2)]);
      expect(r.ignored.single.reason, equals(IgnoredReason.unknownQuestion));
    });

    test('option that is not part of the question is reported', () {
      final r = score([
        const Response(
          participantId: 'p1',
          questionId: 'primary_key_1',
          questionVersion: 1,
          selectedOptionId: 'z',
          displayLanguage: Language.en,
        ),
      ]);
      expect(r.ignored.single.reason, equals(IgnoredReason.unknownOption));
    });

    test('question without an answer key is reported', () {
      final r = scoreResponses(
        responses: [answer('p1', 'primary_key_1', true)],
        questions: testQuestions,
        keys: const [],
      );
      expect(r.ignored.single.reason, equals(IgnoredReason.missingKey));
    });

    test('duplicate answer from the same participant: first one counts', () {
      final r = score([
        answer('p1', 'primary_key_1', false),
        answer('p1', 'primary_key_1', true)
      ]);
      expect(r.scored.single.isCorrect, isFalse);
      expect(r.ignored.single.reason, equals(IgnoredReason.duplicate));
    });

    test(
        'different participants answering the same question are not duplicates',
        () {
      final r = score([
        answer('p1', 'primary_key_1', true),
        answer('p2', 'primary_key_1', true)
      ]);
      expect(r.scored, hasLength(2));
      expect(r.ignored, isEmpty);
    });

    test('keys are matched per question version', () {
      final r = scoreResponses(
        responses: [answer('p1', 'q', true, version: 2)],
        questions: const [
          Question(
              id: 'q',
              version: 1,
              conceptIds: ['primary_key'],
              optionIds: ['a', 'b']),
          Question(
              id: 'q',
              version: 2,
              conceptIds: ['primary_key'],
              optionIds: ['a', 'b']),
        ],
        keys: const [
          AnswerKey(questionId: 'q', questionVersion: 1, correctOptionId: 'a'),
          AnswerKey(questionId: 'q', questionVersion: 2, correctOptionId: 'b'),
        ],
      );
      expect(r.scored.single.isCorrect, isFalse);
    });
  });

  group('evidenceByParticipant', () {
    test('counts attempts and correct answers per concept', () {
      final scored = scoreResponses(
        responses: answers('p1', 'primary_key', 3, 4),
        questions: testQuestions,
        keys: testKeys,
      ).scored;
      final e = evidenceByParticipant(
          scored: scored, conceptIds: ['primary_key'])['p1']!['primary_key']!;
      expect(e.attempts, equals(4));
      expect(e.correct, equals(3));
      expect(e.accuracy, closeTo(0.75, 1e-9));
    });

    test('a question mapped to two concepts counts for both', () {
      final scored = scoreResponses(
        responses: [answer('p1', 'join_1', true)],
        questions: const [
          Question(
              id: 'join_1',
              version: 1,
              conceptIds: ['primary_key', 'foreign_key'],
              optionIds: ['a', 'b']),
        ],
        keys: const [
          AnswerKey(
              questionId: 'join_1', questionVersion: 1, correctOptionId: 'a')
        ],
      ).scored;
      final e =
          evidenceByParticipant(scored: scored, conceptIds: const [])['p1']!;
      expect(e['primary_key']!.attempts, equals(1));
      expect(e['foreign_key']!.attempts, equals(1));
    });

    test('unassessed concepts appear with zero attempts and null accuracy', () {
      final scored = scoreResponses(
        responses: answers('p1', 'primary_key', 1, 1),
        questions: testQuestions,
        keys: testKeys,
      ).scored;
      final e = evidenceByParticipant(
          scored: scored, conceptIds: testConcepts.map((c) => c.id))['p1']!;
      expect(e['foreign_key']!.attempts, equals(0));
      expect(e['foreign_key']!.accuracy, isNull);
    });
  });
}
