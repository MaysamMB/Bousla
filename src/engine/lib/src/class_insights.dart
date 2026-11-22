import 'mastery_estimator.dart';
import 'models.dart';
import 'prerequisite_analyzer.dart';

/// Aggregate view of one concept across a class. Contains no participant IDs.
class ConceptClassSummary {
  const ConceptClassSummary({
    required this.conceptId,
    required this.respondents,
    required this.suppressed,
    this.stateCounts = const {},
    this.pooledAccuracy,
  });

  final String conceptId;

  /// Participants with at least one scored answer on this concept.
  final int respondents;

  /// True when [respondents] is below the minimum group size. Then
  /// [stateCounts] is empty and [pooledAccuracy] is null, so small groups
  /// cannot be traced back to individuals.
  final bool suppressed;
  final Map<MasteryState, int> stateCounts;

  /// Correct answers / all answers on this concept, across respondents.
  final double? pooledAccuracy;

  /// Share of respondents in [MasteryState.possibleDifficulty]; 0 when suppressed.
  double get difficultyShare => suppressed || respondents == 0
      ? 0
      : (stateCounts[MasteryState.possibleDifficulty] ?? 0) / respondents;
}

/// How many participants struggling with [conceptId] also show a possible
/// gap in [prerequisiteId].
class PrerequisiteClassSignal {
  const PrerequisiteClassSignal({
    required this.conceptId,
    required this.prerequisiteId,
    required this.participantsWithPossibleGap,
    required this.participantsStrugglingWithConcept,
  });

  final String conceptId;
  final String prerequisiteId;
  final int participantsWithPossibleGap;
  final int participantsStrugglingWithConcept;
}

class ClassInsights {
  const ClassInsights({
    required this.participantCount,
    required this.minGroupSize,
    required this.concepts,
    required this.prerequisiteSignals,
  });

  final int participantCount;
  final int minGroupSize;

  /// One summary per concept, ordered by [ConceptClassSummary.difficultyShare]
  /// (highest first), then by concept ID. Suppressed concepts come last.
  final List<ConceptClassSummary> concepts;

  /// Only for concepts that are not suppressed, highest count first.
  final List<PrerequisiteClassSignal> prerequisiteSignals;
}

/// Builds the instructor's aggregate view from per-participant masteries.
///
/// [masteriesByParticipant] maps participant ID → concept ID → mastery.
/// Participant IDs are used only for counting and never appear in the output.
ClassInsights buildClassInsights({
  required Map<String, Map<String, ConceptMastery>> masteriesByParticipant,
  required Iterable<Concept> concepts,
  int minGroupSize = 5,
}) {
  final conceptList = concepts.toList();
  final summaries = <ConceptClassSummary>[];
  final suppressedIds = <String>{};

  for (final concept in conceptList) {
    final assessed = [
      for (final m in masteriesByParticipant.values)
        if ((m[concept.id]?.evidence.attempts ?? 0) > 0) m[concept.id]!,
    ];
    if (assessed.length < minGroupSize) {
      suppressedIds.add(concept.id);
      summaries.add(ConceptClassSummary(
          conceptId: concept.id,
          respondents: assessed.length,
          suppressed: true));
      continue;
    }
    final counts = <MasteryState, int>{};
    var attempts = 0, correct = 0;
    for (final m in assessed) {
      counts.update(m.state, (n) => n + 1, ifAbsent: () => 1);
      attempts += m.evidence.attempts;
      correct += m.evidence.correct;
    }
    summaries.add(ConceptClassSummary(
      conceptId: concept.id,
      respondents: assessed.length,
      suppressed: false,
      stateCounts: counts,
      pooledAccuracy: correct / attempts,
    ));
  }

  summaries.sort((a, b) {
    if (a.suppressed != b.suppressed) return a.suppressed ? 1 : -1;
    final byShare = b.difficultyShare.compareTo(a.difficultyShare);
    return byShare != 0 ? byShare : a.conceptId.compareTo(b.conceptId);
  });

  final gapCounts = <String, int>{};
  final strugglingCounts = <String, int>{};
  for (final masteries in masteriesByParticipant.values) {
    for (final m in masteries.values) {
      if (m.state == MasteryState.possibleDifficulty) {
        strugglingCounts.update(m.conceptId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final f
        in analyzePrerequisites(masteries: masteries, concepts: conceptList)) {
      if (f.signal == PrerequisiteSignal.possibleContributingGap) {
        gapCounts.update('${f.conceptId}|${f.prerequisiteId}', (n) => n + 1,
            ifAbsent: () => 1);
      }
    }
  }
  final signals = [
    for (final e in gapCounts.entries)
      if (!suppressedIds.contains(e.key.split('|').first))
        PrerequisiteClassSignal(
          conceptId: e.key.split('|').first,
          prerequisiteId: e.key.split('|').last,
          participantsWithPossibleGap: e.value,
          participantsStrugglingWithConcept:
              strugglingCounts[e.key.split('|').first] ?? 0,
        ),
  ]..sort((a, b) {
      final byCount = b.participantsWithPossibleGap
          .compareTo(a.participantsWithPossibleGap);
      if (byCount != 0) return byCount;
      final byConcept = a.conceptId.compareTo(b.conceptId);
      return byConcept != 0
          ? byConcept
          : a.prerequisiteId.compareTo(b.prerequisiteId);
    });

  return ClassInsights(
    participantCount: masteriesByParticipant.length,
    minGroupSize: minGroupSize,
    concepts: summaries,
    prerequisiteSignals: signals,
  );
}
