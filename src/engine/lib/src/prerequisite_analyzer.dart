import 'mastery_estimator.dart';
import 'models.dart';

/// What the evidence says about one prerequisite of a concept the student
/// may be struggling with.
enum PrerequisiteSignal {
  /// The prerequisite also shows possible difficulty. It may be contributing.
  /// This is a possibility supported by evidence, not a proven cause.
  possibleContributingGap,

  /// Not enough evidence about the prerequisite. Assess it before concluding.
  needsMoreEvidence,

  /// Some evidence, but not clear either way.
  uncertain,

  /// The prerequisite shows demonstrated mastery, so it is an unlikely cause.
  unlikelyCause,
}

class PrerequisiteFinding {
  const PrerequisiteFinding({
    required this.conceptId,
    required this.prerequisiteId,
    required this.signal,
    required this.prerequisiteMastery,
  });

  /// The concept showing possible difficulty.
  final String conceptId;
  final String prerequisiteId;
  final PrerequisiteSignal signal;

  /// The evidence behind [signal]. `null` if the prerequisite was not in the
  /// participant's results at all (treated as needing more evidence).
  final ConceptMastery? prerequisiteMastery;
}

/// For every concept in [masteries] with [MasteryState.possibleDifficulty],
/// classifies each of its direct prerequisites.
///
/// Only direct prerequisites are examined; deeper chains are left to further
/// assessment rather than guessed. Concepts without prerequisites produce no
/// findings.
List<PrerequisiteFinding> analyzePrerequisites({
  required Map<String, ConceptMastery> masteries,
  required Iterable<Concept> concepts,
}) {
  final conceptsById = {for (final c in concepts) c.id: c};
  final findings = <PrerequisiteFinding>[];
  final struggling = masteries.values
      .where((m) => m.state == MasteryState.possibleDifficulty)
      .map((m) => m.conceptId)
      .toList()
    ..sort();
  for (final conceptId in struggling) {
    final concept = conceptsById[conceptId];
    if (concept == null) continue;
    for (final prereqId in concept.prerequisites) {
      final prereq = masteries[prereqId];
      findings.add(PrerequisiteFinding(
        conceptId: conceptId,
        prerequisiteId: prereqId,
        signal: _signalFor(prereq),
        prerequisiteMastery: prereq,
      ));
    }
  }
  return findings;
}

PrerequisiteSignal _signalFor(ConceptMastery? prereq) =>
    switch (prereq?.state) {
      MasteryState.possibleDifficulty =>
        PrerequisiteSignal.possibleContributingGap,
      MasteryState.demonstratedMastery => PrerequisiteSignal.unlikelyCause,
      MasteryState.emerging => PrerequisiteSignal.uncertain,
      MasteryState.insufficientEvidence ||
      null =>
        PrerequisiteSignal.needsMoreEvidence,
    };
