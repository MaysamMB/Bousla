import 'package:bousla_engine/bousla_engine.dart';

LocalizedText t(String ar, String en) => LocalizedText(ar: ar, en: en);

/// Small hand-made course: relational_model → primary_key → foreign_key.
final testConcepts = [
  Concept(
      id: 'relational_model', name: t('النموذج العلائقي', 'Relational Model')),
  Concept(
      id: 'primary_key',
      name: t('المفتاح الأساسي', 'Primary Key'),
      prerequisites: ['relational_model']),
  Concept(
      id: 'foreign_key',
      name: t('المفتاح الخارجي', 'Foreign Key'),
      prerequisites: ['primary_key']),
];

/// Four questions per concept, IDs `<concept>_<n>`, correct option always `a`.
final testQuestions = [
  for (final c in ['relational_model', 'primary_key', 'foreign_key'])
    for (var n = 1; n <= 4; n++)
      Question(
          id: '${c}_$n',
          version: 1,
          conceptIds: [c],
          optionIds: ['a', 'b', 'c', 'd']),
];

final testKeys = [
  for (final q in testQuestions)
    AnswerKey(questionId: q.id, questionVersion: 1, correctOptionId: 'a'),
];

Response answer(String participant, String questionId, bool correct,
        {Language lang = Language.ar, int version = 1}) =>
    Response(
      participantId: participant,
      questionId: questionId,
      questionVersion: version,
      selectedOptionId: correct ? 'a' : 'b',
      displayLanguage: lang,
    );

/// Answers [right] of [total] questions on [concept] correctly (total ≤ 4).
List<Response> answers(String participant, String concept, int right, int total,
        {Language lang = Language.ar}) =>
    [
      for (var n = 1; n <= total; n++)
        answer(participant, '${concept}_$n', n <= right, lang: lang)
    ];

/// Runs scoring → evidence → mastery for every participant.
Map<String, Map<String, ConceptMastery>> masteriesFor(
    List<Response> responses) {
  final scored = scoreResponses(
          responses: responses, questions: testQuestions, keys: testKeys)
      .scored;
  final evidence = evidenceByParticipant(
      scored: scored, conceptIds: testConcepts.map((c) => c.id));
  return {for (final e in evidence.entries) e.key: estimateAll(e.value)};
}

ConceptEvidence ev(int attempts, int correct) =>
    ConceptEvidence(conceptId: 'x', attempts: attempts, correct: correct);
