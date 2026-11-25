import 'package:bousla_engine/bousla_engine.dart';

/// Suggested classroom actions, not diagnoses or AI-generated conclusions.
enum TeachingActionKind { reviewPrerequisite, reviewConcept, assessFurther }

class TeachingAction {
  const TeachingAction({
    required this.conceptId,
    required this.kind,
    required this.affectedCount,
    required this.groupCount,
    this.relatedConceptId,
  });

  final String conceptId;
  final TeachingActionKind kind;
  final int affectedCount;
  final int groupCount;
  final String? relatedConceptId;
}

/// Conservative, provisional prioritization for the current session only.
/// Review a prerequisite first when at least minGroupSize respondents show
/// both difficulties; then review concepts where at least half of respondents
/// show possible difficulty; then collect evidence when at least half lack it.
/// Suppressed and uncovered concepts are excluded. At most one action per
/// concept is returned. No individual identifiers or raw answers are needed.
List<TeachingAction> prioritizeTeachingActions(
  ClassInsights insights, {
  required Set<String> coveredConceptIds,
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final visible = {
    for (final c in insights.concepts)
      if (!c.suppressed &&
          c.respondents > 0 &&
          c.respondents >= insights.minGroupSize &&
          coveredConceptIds.contains(c.conceptId))
        c.conceptId: c,
  };
  final actions = <TeachingAction>[];
  final used = <String>{};

  void add(TeachingAction action) {
    if (actions.length < limit && used.add(action.conceptId)) {
      actions.add(action);
    }
  }

  final signals = insights.prerequisiteSignals.toList()
    ..sort((a, b) {
      final byCount = b.participantsWithPossibleGap
          .compareTo(a.participantsWithPossibleGap);
      if (byCount != 0) return byCount;
      final byPrerequisite = a.prerequisiteId.compareTo(b.prerequisiteId);
      return byPrerequisite != 0
          ? byPrerequisite
          : a.conceptId.compareTo(b.conceptId);
    });
  for (final signal in signals) {
    if (visible.containsKey(signal.conceptId) &&
        visible.containsKey(signal.prerequisiteId) &&
        signal.participantsWithPossibleGap >= insights.minGroupSize &&
        signal.participantsWithPossibleGap > 0) {
      add(TeachingAction(
        conceptId: signal.prerequisiteId,
        kind: TeachingActionKind.reviewPrerequisite,
        relatedConceptId: signal.conceptId,
        affectedCount: signal.participantsWithPossibleGap,
        groupCount: signal.participantsStrugglingWithConcept,
      ));
    }
  }

  final ranked = visible.values.toList()
    ..sort((a, b) {
      final byShare = b.difficultyShare.compareTo(a.difficultyShare);
      return byShare != 0 ? byShare : a.conceptId.compareTo(b.conceptId);
    });
  for (final concept in ranked) {
    if (concept.difficultyShare >= 0.5) {
      add(TeachingAction(
        conceptId: concept.conceptId,
        kind: TeachingActionKind.reviewConcept,
        affectedCount: concept.stateCounts[MasteryState.possibleDifficulty] ?? 0,
        groupCount: concept.respondents,
      ));
    }
  }
  double insufficientShare(ConceptClassSummary c) =>
      (c.stateCounts[MasteryState.insufficientEvidence] ?? 0) / c.respondents;
  ranked.sort((a, b) {
    final byShare = insufficientShare(b).compareTo(insufficientShare(a));
    return byShare != 0 ? byShare : a.conceptId.compareTo(b.conceptId);
  });
  for (final concept in ranked) {
    if (insufficientShare(concept) >= 0.5) {
      add(TeachingAction(
        conceptId: concept.conceptId,
        kind: TeachingActionKind.assessFurther,
        affectedCount: concept.stateCounts[MasteryState.insufficientEvidence] ?? 0,
        groupCount: concept.respondents,
      ));
    }
  }
  return List.unmodifiable(actions);
}
