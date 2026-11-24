import 'package:bousla_engine/bousla_engine.dart';

/// Computes aggregate classroom insights from session responses.
/// No participant ID is included in the result.
ClassInsights computeClassInsights({
  required List<Response> responses,
  required List<Question> questions,
  required List<AnswerKey> keys,
  required List<Concept> concepts,
}) {
  final result = scoreResponses(
    responses: responses,
    questions: questions,
    keys: keys,
  );

  final evidence = evidenceByParticipant(
    scored: result.scored,
    conceptIds: [for (final c in concepts) c.id],
  );

  return buildClassInsights(
    masteriesByParticipant: {
      for (final e in evidence.entries)
        e.key: estimateAll(e.value),
    },
    concepts: concepts,
  );
}