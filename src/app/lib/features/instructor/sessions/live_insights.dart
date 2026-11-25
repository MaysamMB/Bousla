import 'package:bousla_engine/bousla_engine.dart';

/// Smallest group whose per-concept results are shown to the instructor.
/// Below it, only [SessionOverview] is shown (no numbers per concept), so
/// one or two students' answers cannot be read concept by concept.
const classMinGroupSize = 3;

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
    minGroupSize: classMinGroupSize,
  );
}

/// The whole session at a glance, for when fewer than [classMinGroupSize]
/// students answered: all scored answers together, and the concepts with
/// the most wrong answers (names only, no numbers per concept).
class SessionOverview {
  const SessionOverview({
    required this.answers,
    required this.correct,
    required this.focusConceptIds,
  });

  /// Scored answers in the session, and how many were right.
  final int answers;
  final int correct;

  /// Concepts with at least one wrong answer, most wrong answers first
  /// (then by ID), at most three.
  final List<String> focusConceptIds;

  int get percent => answers == 0 ? 0 : (correct * 100 / answers).round();
}

SessionOverview sessionOverview({
  required List<Response> responses,
  required List<Question> questions,
  required List<AnswerKey> keys,
  Set<String>? coveredConceptIds,
  int limit = 3,
}) {
  final scored = scoreResponses(
    responses: responses,
    questions: questions,
    keys: keys,
  ).scored;
  final wrong = <String, int>{};
  var correct = 0;
  for (final s in scored) {
    if (s.isCorrect) {
      correct++;
      continue;
    }
    for (final id in s.question.conceptIds) {
      if (coveredConceptIds == null || coveredConceptIds.contains(id)) {
        wrong.update(id, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  final focus = wrong.keys.toList()
    ..sort((a, b) {
      final byCount = wrong[b]!.compareTo(wrong[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return SessionOverview(
    answers: scored.length,
    correct: correct,
    focusConceptIds: focus.take(limit).toList(),
  );
}
