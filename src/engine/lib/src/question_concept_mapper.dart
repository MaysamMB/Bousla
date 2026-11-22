import 'scoring.dart';

/// Observed evidence for one concept: how many scored answers touched it and
/// how many of those were correct. This is measured data, not an estimate.
class ConceptEvidence {
  const ConceptEvidence(
      {required this.conceptId, required this.attempts, required this.correct});

  final String conceptId;
  final int attempts;
  final int correct;

  /// `null` when there are no attempts.
  double? get accuracy => attempts == 0 ? null : correct / attempts;
}

/// Groups scored responses by concept for each participant.
///
/// A question mapped to several concepts counts as evidence for each of them.
/// Concepts listed in [conceptIds] with no answers appear with zero attempts,
/// so "not assessed" stays visible instead of disappearing.
Map<String, Map<String, ConceptEvidence>> evidenceByParticipant({
  required Iterable<ScoredResponse> scored,
  required Iterable<String> conceptIds,
}) {
  final attempts = <String, Map<String, int>>{};
  final correct = <String, Map<String, int>>{};
  for (final s in scored) {
    final pid = s.response.participantId;
    for (final cid in s.question.conceptIds) {
      attempts
          .putIfAbsent(pid, () => {})
          .update(cid, (n) => n + 1, ifAbsent: () => 1);
      if (s.isCorrect) {
        correct
            .putIfAbsent(pid, () => {})
            .update(cid, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  final allConcepts = conceptIds.toList();
  return {
    for (final pid in attempts.keys)
      pid: {
        for (final cid in {...allConcepts, ...attempts[pid]!.keys})
          cid: ConceptEvidence(
            conceptId: cid,
            attempts: attempts[pid]![cid] ?? 0,
            correct: correct[pid]?[cid] ?? 0,
          ),
      },
  };
}
