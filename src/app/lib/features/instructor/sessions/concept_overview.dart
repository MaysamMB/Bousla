import 'package:bousla_engine/bousla_engine.dart';

import 'teaching_actions.dart';

/// Counts concepts, not distinct students. No cross-concept student totals.
class ConceptOverview {
  const ConceptOverview({
    required this.visible,
    required this.coveredCount,
    required this.reviewCount,
    required this.assessCount,
  });

  final List<ConceptClassSummary> visible;
  final int coveredCount;
  final int reviewCount;
  final int assessCount;

  int get hiddenCount => coveredCount - visible.length;
}

const overviewStates = [
  MasteryState.possibleDifficulty,
  MasteryState.emerging,
  MasteryState.demonstratedMastery,
  MasteryState.insufficientEvidence,
];

/// Only session-covered concepts with enough respondents are displayed.
/// Review/assess thresholds are provisional and match Teaching Actions.
ConceptOverview buildConceptOverview(
  ClassInsights insights,
  Set<String> coveredConceptIds,
) {
  final visible = insights.concepts.where((c) =>
      coveredConceptIds.contains(c.conceptId) &&
      !c.suppressed &&
      c.respondents > 0 &&
      c.respondents >= insights.minGroupSize).toList()
    ..sort((a, b) {
      final byDifficulty = b.difficultyShare.compareTo(a.difficultyShare);
      return byDifficulty != 0
          ? byDifficulty
          : a.conceptId.compareTo(b.conceptId);
    });
  // Use exactly the same policy as the action card, without its top-three cap.
  // A foundation may be prioritized even if fewer than half its respondents
  // show difficulty; counting by difficulty alone would miss that action.
  final actions = prioritizeTeachingActions(insights,
      coveredConceptIds: coveredConceptIds, limit: visible.length);
  final review = actions.where((a) =>
      a.kind != TeachingActionKind.assessFurther).length;
  final assess = actions.where((a) =>
      a.kind == TeachingActionKind.assessFurther).length;
  return ConceptOverview(
    visible: List.unmodifiable(visible),
    coveredCount: coveredConceptIds.length,
    reviewCount: review,
    assessCount: assess,
  );
}
