import 'mastery_estimator.dart';
import 'models.dart';
import 'prerequisite_analyzer.dart';

enum RecommendationReason {
  /// A prerequisite that may be contributing to a difficulty. Foundations first.
  reviewPrerequisite,

  /// The concept itself shows possible difficulty.
  reviewConcept,

  /// Some evidence, not yet solid. Practice to strengthen it.
  practice,

  /// Not enough evidence about a prerequisite of a difficult concept.
  /// The next step is more assessment, not a conclusion.
  assessMore,
}

class Recommendation {
  const Recommendation({
    required this.conceptId,
    required this.reason,
    required this.resources,
    this.relatedConceptId,
  });

  final String conceptId;
  final RecommendationReason reason;

  /// For prerequisite reasons: the concept that showed possible difficulty.
  final String? relatedConceptId;

  /// Approved resources for [conceptId], preferred language first. May be
  /// empty (for example for [RecommendationReason.assessMore]).
  final List<Resource> resources;
}

/// Chooses next steps for one participant.
///
/// Order: prerequisites with a possible contributing gap, then concepts with
/// possible difficulty, then emerging concepts whose accuracy is below the
/// mastery level, then prerequisites that need more assessment. Emerging
/// concepts answered at mastery accuracy (just too few answers) get no
/// practice recommendation. Each concept appears at most once. Only
/// [ReviewStatus.approved] resources are used.
List<Recommendation> recommend({
  required Map<String, ConceptMastery> masteries,
  required Iterable<Concept> concepts,
  required Iterable<Resource> resources,
  required Language preferredLanguage,
  MasteryThresholds thresholds = const MasteryThresholds(),
  int maxRecommendations = 3,
  int maxResourcesEach = 2,
}) {
  final findings =
      analyzePrerequisites(masteries: masteries, concepts: concepts);
  final approved =
      resources.where((r) => r.status == ReviewStatus.approved).toList();
  final used = <String>{};
  final out = <Recommendation>[];

  void add(String conceptId, RecommendationReason reason, {String? related}) {
    if (out.length >= maxRecommendations || !used.add(conceptId)) return;
    out.add(Recommendation(
      conceptId: conceptId,
      reason: reason,
      relatedConceptId: related,
      resources: reason == RecommendationReason.assessMore
          ? const []
          : _resourcesFor(conceptId, approved, preferredLanguage)
              .take(maxResourcesEach)
              .toList(),
    ));
  }

  List<String> idsIn(MasteryState state) => (masteries.values
      .where((m) => m.state == state)
      .map((m) => m.conceptId)
      .toList()
    ..sort());

  for (final f in findings
      .where((f) => f.signal == PrerequisiteSignal.possibleContributingGap)) {
    add(f.prerequisiteId, RecommendationReason.reviewPrerequisite,
        related: f.conceptId);
  }
  for (final id in idsIn(MasteryState.possibleDifficulty)) {
    add(id, RecommendationReason.reviewConcept);
  }
  for (final id in idsIn(MasteryState.emerging)) {
    final accuracy = masteries[id]!.evidence.accuracy ?? 0;
    if (accuracy < thresholds.masteryAccuracyAtLeast)
      add(id, RecommendationReason.practice);
  }
  for (final f in findings
      .where((f) => f.signal == PrerequisiteSignal.needsMoreEvidence)) {
    add(f.prerequisiteId, RecommendationReason.assessMore,
        related: f.conceptId);
  }
  return out;
}

Iterable<Resource> _resourcesFor(
    String conceptId, List<Resource> approved, Language preferred) {
  int rank(Resource r) => switch (r.language) {
        ResourceLanguage.both => 1,
        ResourceLanguage.ar => preferred == Language.ar ? 0 : 2,
        ResourceLanguage.en => preferred == Language.en ? 0 : 2,
      };
  final matching =
      approved.where((r) => r.conceptIds.contains(conceptId)).toList()
        ..sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0 ? byRank : a.id.compareTo(b.id);
        });
  return matching;
}
