// A student's personal feedback for one session (docs/architecture.md §6-§7,
// Option A): computed by the instructor app from the engine's results and
// stored as sessions/{CODE}/feedback/{participant uid}. The student can read
// only their own, and only once the instructor has released feedback.
//
// Everything the student's screen shows is in the document (concept names,
// resource titles and links), because the security rules do not let
// students list concepts or resources. It never holds answer keys, names or
// the student's raw answers: evidence is counts only.
import 'package:bousla_engine/bousla_engine.dart';

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

LocalizedText _text(Object? json) {
  final m = json is Map ? json : const {};
  return LocalizedText(
    ar: (m['ar'] as String?) ?? '',
    en: (m['en'] as String?) ?? '',
  );
}

Map<String, String> _textJson(LocalizedText t) => {'ar': t.ar, 'en': t.en};

List<Map<String, dynamic>> _list(Object? json) => [
      if (json is List)
        for (final e in json)
          if (e is Map) Map<String, dynamic>.from(e),
    ];

/// One concept's state for this student, with its evidence.
class FeedbackConcept {
  const FeedbackConcept({
    required this.conceptId,
    required this.name,
    required this.state,
    required this.attempts,
    required this.correct,
    this.prerequisites = const [],
  });

  /// From the course concept and this student's estimate (null when the
  /// session had no question on it: insufficient evidence, 0 of 0).
  factory FeedbackConcept.from(Concept concept, ConceptMastery? mastery) =>
      FeedbackConcept(
        conceptId: concept.id,
        name: concept.name,
        state: mastery?.state ?? MasteryState.insufficientEvidence,
        attempts: mastery?.evidence.attempts ?? 0,
        correct: mastery?.evidence.correct ?? 0,
        prerequisites: List.unmodifiable(concept.prerequisites),
      );

  final String conceptId;
  final LocalizedText name;
  final MasteryState state;

  /// Evidence shown next to the state: "correct of attempts".
  final int attempts;
  final int correct;

  /// IDs of this concept's direct prerequisites (for the knowledge map).
  final List<String> prerequisites;

  Map<String, dynamic> toJson() => {
        'concept_id': conceptId,
        'name': _textJson(name),
        'state': state.name,
        'attempts': attempts,
        'correct': correct,
        'prerequisites': prerequisites,
      };

  factory FeedbackConcept.fromJson(Map<String, dynamic> json) =>
      FeedbackConcept(
        conceptId: json['concept_id'] as String,
        name: _text(json['name']),
        state: _byName(
          MasteryState.values,
          json['state'],
          MasteryState.insufficientEvidence,
        ),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        prerequisites: [
          if (json['prerequisites'] case final List list)
            for (final p in list)
              if (p is String) p,
        ],
      );
}

/// A prerequisite that may be contributing to a concept's difficulty
/// (a possibility, never a diagnosis).
class FeedbackHint {
  const FeedbackHint({
    required this.conceptId,
    required this.prerequisiteId,
    required this.signal,
  });

  final String conceptId;
  final String prerequisiteId;
  final PrerequisiteSignal signal;

  Map<String, dynamic> toJson() => {
        'concept_id': conceptId,
        'prerequisite_id': prerequisiteId,
        'signal': signal.name,
      };

  factory FeedbackHint.fromJson(Map<String, dynamic> json) => FeedbackHint(
        conceptId: json['concept_id'] as String,
        prerequisiteId: json['prerequisite_id'] as String,
        signal: _byName(
          PrerequisiteSignal.values,
          json['signal'],
          PrerequisiteSignal.uncertain,
        ),
      );
}

/// An approved resource, copied into the feedback so the student can open it.
class FeedbackResource {
  const FeedbackResource({
    required this.id,
    required this.title,
    required this.type,
    this.url,
    this.description,
  });

  final String id;
  final LocalizedText title;
  final ResourceType type;
  final String? url;

  /// What the resource covers, when it has one (e.g. what to do in an
  /// activity). Older feedback documents have none.
  final LocalizedText? description;

  factory FeedbackResource.from(Resource r) => FeedbackResource(
        id: r.id,
        title: r.title,
        type: r.type,
        url: r.url,
        description: r.description,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': _textJson(title),
        'type': type.name,
        'url': url,
        if (description case final d?) 'description': _textJson(d),
      };

  factory FeedbackResource.fromJson(Map<String, dynamic> json) =>
      FeedbackResource(
        id: json['id'] as String,
        title: _text(json['title']),
        type: _byName(ResourceType.values, json['type'], ResourceType.activity),
        url: json['url'] as String?,
        description:
            json['description'] == null ? null : _text(json['description']),
      );
}

/// A next step from the engine's `recommend`.
class FeedbackRecommendation {
  const FeedbackRecommendation({
    required this.conceptId,
    required this.reason,
    this.relatedConceptId,
    this.resources = const [],
  });

  final String conceptId;
  final RecommendationReason reason;
  final String? relatedConceptId;
  final List<FeedbackResource> resources;

  factory FeedbackRecommendation.from(Recommendation r) =>
      FeedbackRecommendation(
        conceptId: r.conceptId,
        reason: r.reason,
        relatedConceptId: r.relatedConceptId,
        resources: [for (final res in r.resources) FeedbackResource.from(res)],
      );

  Map<String, dynamic> toJson() => {
        'concept_id': conceptId,
        'reason': reason.name,
        'related_concept_id': relatedConceptId,
        'resources': [for (final r in resources) r.toJson()],
      };

  factory FeedbackRecommendation.fromJson(Map<String, dynamic> json) =>
      FeedbackRecommendation(
        conceptId: json['concept_id'] as String,
        reason: _byName(
          RecommendationReason.values,
          json['reason'],
          RecommendationReason.assessMore,
        ),
        relatedConceptId: json['related_concept_id'] as String?,
        resources: [
          for (final r in _list(json['resources']))
            FeedbackResource.fromJson(r),
        ],
      );
}

/// Where an explanation came from.
enum ExplanationSource {
  /// Written by the model and passed the engine's guards. Shown with an
  /// "AI-generated" label.
  ai,

  /// The deterministic template (no model, or the model or a guard failed).
  template,
}

/// A short personal explanation in both languages (AI level 2 or template).
class FeedbackExplanation {
  const FeedbackExplanation({
    required this.text,
    required this.source,
    this.model,
  });

  final LocalizedText text;
  final ExplanationSource source;

  /// The model that wrote it, when [source] is [ExplanationSource.ai].
  final String? model;

  Map<String, dynamic> toJson() => {
        'text': _textJson(text),
        'source': source.name,
        'model': model,
      };

  factory FeedbackExplanation.fromJson(Map<String, dynamic> json) =>
      FeedbackExplanation(
        text: _text(json['text']),
        source: _byName(
          ExplanationSource.values,
          json['source'],
          ExplanationSource.template,
        ),
        model: json['model'] as String?,
      );
}

/// One student's feedback for one session.
class StudentFeedback {
  const StudentFeedback({
    required this.language,
    required this.concepts,
    this.hints = const [],
    this.recommendations = const [],
    this.explanation,
  });

  /// The language the student mostly answered in; shown first.
  final Language language;
  final List<FeedbackConcept> concepts;
  final List<FeedbackHint> hints;
  final List<FeedbackRecommendation> recommendations;
  final FeedbackExplanation? explanation;

  Map<String, dynamic> toJson() => {
        'language': language.name,
        'concepts': [for (final c in concepts) c.toJson()],
        'prerequisite_hints': [for (final h in hints) h.toJson()],
        'recommendations': [for (final r in recommendations) r.toJson()],
        'explanation': explanation?.toJson(),
      };

  factory StudentFeedback.fromJson(Map<String, dynamic> json) {
    final explanation = json['explanation'];
    return StudentFeedback(
      language: json['language'] == 'en' ? Language.en : Language.ar,
      concepts: [
        for (final c in _list(json['concepts'])) FeedbackConcept.fromJson(c),
      ],
      hints: [
        for (final h in _list(json['prerequisite_hints']))
          FeedbackHint.fromJson(h),
      ],
      recommendations: [
        for (final r in _list(json['recommendations']))
          FeedbackRecommendation.fromJson(r),
      ],
      explanation: explanation is Map
          ? FeedbackExplanation.fromJson(Map<String, dynamic>.from(explanation))
          : null,
    );
  }
}
