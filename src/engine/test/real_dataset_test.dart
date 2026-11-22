// Loads data/courses/database-systems and runs the whole engine on
// synthetic responses. Run from src/engine.
import 'dart:convert';
import 'dart:io';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

dynamic _read(String name) => jsonDecode(
    File('../../data/courses/database-systems/$name').readAsStringSync());

void main() {
  final concepts = [
    for (final j in _read('concepts.json') as List)
      Concept.fromJson(j as Map<String, dynamic>)
  ];
  final questions = [
    for (final j in _read('questions.json') as List)
      Question.fromJson(j as Map<String, dynamic>)
  ];
  final keys =
      AnswerKey.listFromJson(_read('answer_keys.json') as Map<String, dynamic>);
  final resources = [
    for (final j in _read('resources.json') as List)
      Resource.fromJson(j as Map<String, dynamic>)
  ];
  final correctById = {for (final k in keys) k.questionId: k.correctOptionId};

  /// Synthetic student: answers every question; correct unless the question
  /// touches one of [weak].
  List<Response> student(String id, Set<String> weak, Language lang) => [
        for (final q in questions)
          Response(
            participantId: id,
            questionId: q.id,
            questionVersion: q.version,
            selectedOptionId: q.conceptIds.any(weak.contains)
                ? q.optionIds.firstWhere((o) => o != correctById[q.id])
                : correctById[q.id]!,
            displayLanguage: lang,
          ),
      ];

  test('dataset loads: 10 concepts, 20 questions, one key per question', () {
    expect(concepts, hasLength(10));
    expect(questions, hasLength(20));
    expect(keys, hasLength(20));
    expect(resources, hasLength(10));
  });

  test(
      'all answers correct → every concept demonstrated or emerging, nothing to fix',
      () {
    final scored = scoreResponses(
      responses: student('s1', const {}, Language.ar),
      questions: questions,
      keys: keys,
    );
    expect(scored.ignored, isEmpty);
    final masteries = estimateAll(evidenceByParticipant(
        scored: scored.scored, conceptIds: concepts.map((c) => c.id))['s1']!);
    expect(
        masteries.values.any((m) => m.state == MasteryState.possibleDifficulty),
        isFalse);
  });

  test(
      'weak in primary_key and sql_join → joins flagged, foreign/primary key traced',
      () {
    final scored = scoreResponses(
      responses: student('s1', const {'primary_key', 'sql_join'}, Language.en),
      questions: questions,
      keys: keys,
    ).scored;
    final masteries = estimateAll(evidenceByParticipant(
        scored: scored, conceptIds: concepts.map((c) => c.id))['s1']!);
    expect(
        masteries['sql_join']!.state, equals(MasteryState.possibleDifficulty));
    expect(masteries['primary_key']!.state,
        equals(MasteryState.possibleDifficulty));

    final findings =
        analyzePrerequisites(masteries: masteries, concepts: concepts);
    final fkForJoin = findings.firstWhere(
        (f) => f.conceptId == 'sql_join' && f.prerequisiteId == 'foreign_key');
    // foreign_key itself was answered correctly, so it is not blamed.
    expect(fkForJoin.signal,
        isNot(equals(PrerequisiteSignal.possibleContributingGap)));
  });

  test('draft resources (pending review) are not recommended', () {
    final scored = scoreResponses(
      responses: student('s1', const {'normalization'}, Language.ar),
      questions: questions,
      keys: keys,
    ).scored;
    final masteries = estimateAll(evidenceByParticipant(
        scored: scored, conceptIds: concepts.map((c) => c.id))['s1']!);
    final recs = recommend(
      masteries: masteries,
      concepts: concepts,
      resources: resources,
      preferredLanguage: Language.ar,
    );
    expect(recs.first.conceptId, equals('normalization'));
    expect(recs.first.reason, equals(RecommendationReason.reviewConcept));
    expect(recs.expand((r) => r.resources), isEmpty);
  });

  test(
      'class of 6 synthetic students in mixed languages gives aggregate insights',
      () {
    final responses = [
      for (var i = 0; i < 6; i++)
        ...student('s$i', i < 4 ? const {'normalization'} : const {},
            i.isEven ? Language.ar : Language.en),
    ];
    final scored =
        scoreResponses(responses: responses, questions: questions, keys: keys)
            .scored;
    final evidence = evidenceByParticipant(
        scored: scored, conceptIds: concepts.map((c) => c.id));
    final insights = buildClassInsights(
      masteriesByParticipant: {
        for (final e in evidence.entries) e.key: estimateAll(e.value)
      },
      concepts: concepts,
    );
    expect(insights.participantCount, equals(6));
    expect(insights.concepts.first.conceptId, equals('normalization'));
    expect(insights.concepts.first.stateCounts[MasteryState.possibleDifficulty],
        equals(4));
  });
}
