import 'question_concept_mapper.dart';

/// Rule-based mastery states. These are estimates from limited evidence,
/// never diagnoses.
enum MasteryState {
  /// Too few answers to say anything.
  insufficientEvidence,

  /// Enough answers, and accuracy is low. The student may need to review this.
  possibleDifficulty,

  /// Some evidence, but not enough or not clear enough for either conclusion.
  emerging,

  /// Enough answers with high accuracy.
  demonstratedMastery,
}

/// Starter thresholds. Provisional, configurable, not scientifically validated.
class MasteryThresholds {
  const MasteryThresholds({
    this.minAttemptsForAnyEstimate = 2,
    this.difficultyAccuracyBelow = 0.5,
    this.minAttemptsForMastery = 3,
    this.masteryAccuracyAtLeast = 0.75,
  })  : assert(minAttemptsForAnyEstimate >= 1),
        assert(minAttemptsForMastery >= minAttemptsForAnyEstimate);

  final int minAttemptsForAnyEstimate;
  final double difficultyAccuracyBelow;
  final int minAttemptsForMastery;
  final double masteryAccuracyAtLeast;
}

class ConceptMastery {
  const ConceptMastery({required this.evidence, required this.state});

  /// The observed data the estimate is based on, kept so the UI can show why.
  final ConceptEvidence evidence;
  final MasteryState state;

  String get conceptId => evidence.conceptId;
}

/// Estimates a state from evidence. Rules are checked in this order:
/// 1. fewer than [MasteryThresholds.minAttemptsForAnyEstimate] attempts → insufficient evidence
/// 2. accuracy below [MasteryThresholds.difficultyAccuracyBelow] → possible difficulty
/// 3. at least [MasteryThresholds.minAttemptsForMastery] attempts and accuracy at
///    least [MasteryThresholds.masteryAccuracyAtLeast] → demonstrated mastery
/// 4. otherwise → emerging
ConceptMastery estimateMastery(
  ConceptEvidence evidence, {
  MasteryThresholds thresholds = const MasteryThresholds(),
}) {
  final accuracy = evidence.accuracy;
  final MasteryState state;
  if (evidence.attempts < thresholds.minAttemptsForAnyEstimate ||
      accuracy == null) {
    state = MasteryState.insufficientEvidence;
  } else if (accuracy < thresholds.difficultyAccuracyBelow) {
    state = MasteryState.possibleDifficulty;
  } else if (evidence.attempts >= thresholds.minAttemptsForMastery &&
      accuracy >= thresholds.masteryAccuracyAtLeast) {
    state = MasteryState.demonstratedMastery;
  } else {
    state = MasteryState.emerging;
  }
  return ConceptMastery(evidence: evidence, state: state);
}

/// Applies [estimateMastery] to every concept of one participant.
Map<String, ConceptMastery> estimateAll(
  Map<String, ConceptEvidence> evidence, {
  MasteryThresholds thresholds = const MasteryThresholds(),
}) =>
    {
      for (final e in evidence.entries)
        e.key: estimateMastery(e.value, thresholds: thresholds)
    };
