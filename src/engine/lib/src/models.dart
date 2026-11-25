/// Data models shared by the engine, the instructor app and the student portal.
///
/// IDs are language-independent. Text is stored as [LocalizedText] so Arabic
/// and English always travel together.
library;

enum Language {
  ar,
  en;

  static Language parse(String value) => switch (value) {
        'ar' => Language.ar,
        'en' => Language.en,
        _ => throw FormatException('Unknown language "$value"'),
      };
}

/// Text available in Arabic and English.
class LocalizedText {
  const LocalizedText({required this.ar, required this.en});

  final String ar;
  final String en;

  String of(Language language) => language == Language.ar ? ar : en;

  factory LocalizedText.fromJson(Map<String, dynamic> json) =>
      LocalizedText(ar: json['ar'] as String, en: json['en'] as String);
}

enum ReviewStatus {
  pendingReview,
  approved,
  rejected;

  static ReviewStatus parse(String value) => switch (value) {
        'pending_review' => ReviewStatus.pendingReview,
        'approved' => ReviewStatus.approved,
        'rejected' => ReviewStatus.rejected,
        _ => throw FormatException('Unknown review status "$value"'),
      };
}

ReviewStatus _statusOf(Map<String, dynamic> json) {
  final provenance = json['provenance'];
  if (provenance is Map<String, dynamic> && provenance['status'] is String) {
    return ReviewStatus.parse(provenance['status'] as String);
  }
  return ReviewStatus.pendingReview;
}

class Concept {
  const Concept({
    required this.id,
    required this.name,
    this.prerequisites = const [],
    this.status = ReviewStatus.approved,
  });

  final String id;
  final LocalizedText name;

  /// IDs of concepts that should be understood before this one.
  final List<String> prerequisites;
  final ReviewStatus status;

  factory Concept.fromJson(Map<String, dynamic> json) => Concept(
        id: json['id'] as String,
        name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
        prerequisites: [
          for (final p in (json['prerequisites'] as List? ?? const []))
            p as String
        ],
        status: _statusOf(json),
      );
}

/// A multiple-choice question. Holds no answer; keys are [AnswerKey]s.
class Question {
  const Question({
    required this.id,
    required this.version,
    required this.conceptIds,
    required this.optionIds,
    this.status = ReviewStatus.approved,
  });

  final String id;
  final int version;
  final List<String> conceptIds;
  final List<String> optionIds;
  final ReviewStatus status;

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        version: json['version'] as int,
        conceptIds: [for (final c in json['concept_ids'] as List) c as String],
        optionIds: [
          for (final o in json['options'] as List)
            (o as Map<String, dynamic>)['id'] as String
        ],
        status: _statusOf(json),
      );
}

/// The correct option for one version of one question.
class AnswerKey {
  const AnswerKey({
    required this.questionId,
    required this.questionVersion,
    required this.correctOptionId,
  });

  final String questionId;
  final int questionVersion;
  final String correctOptionId;

  /// Reads `answer_keys.json`, where keys without a version apply to version 1.
  static List<AnswerKey> listFromJson(Map<String, dynamic> json) => [
        for (final entry in json.entries)
          AnswerKey(
            questionId: entry.key,
            questionVersion:
                ((entry.value as Map<String, dynamic>)['version'] as int?) ?? 1,
            correctOptionId: (entry.value
                as Map<String, dynamic>)['correct_option_id'] as String,
          ),
      ];
}

enum ResourceType {
  activity,
  link,
  video,
  file;

  static ResourceType parse(String value) => ResourceType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => throw FormatException('Unknown resource type "$value"'),
      );
}

/// Language a resource is written in. [both] means bilingual.
enum ResourceLanguage {
  ar,
  en,
  both;

  static ResourceLanguage parse(String value) =>
      ResourceLanguage.values.firstWhere(
        (l) => l.name == value,
        orElse: () =>
            throw FormatException('Unknown resource language "$value"'),
      );
}

class Resource {
  const Resource({
    required this.id,
    required this.conceptIds,
    required this.type,
    required this.language,
    required this.title,
    this.url,
    this.status = ReviewStatus.approved,
    this.description,
    this.source,
    this.whereToFind,
    this.searchQuery,
    this.sourceLocation,
  });

  final String id;
  final List<String> conceptIds;
  final ResourceType type;
  final ResourceLanguage language;
  final LocalizedText title;
  final String? url;
  final ReviewStatus status;

  /// What the resource covers (optional).
  final LocalizedText? description;

  /// `instructor`, `ai_draft` or `team` (provenance.source), when known.
  final String? source;

  /// AI suggestions only: where to look, words to search for, and where in
  /// the instructor's material. Never a link (see resource_suggestions.dart).
  final LocalizedText? whereToFind;
  final String? searchQuery;
  final String? sourceLocation;

  factory Resource.fromJson(Map<String, dynamic> json) => Resource(
        id: json['id'] as String,
        conceptIds: [for (final c in json['concept_ids'] as List) c as String],
        type: ResourceType.parse(json['type'] as String),
        language: ResourceLanguage.parse(json['language'] as String),
        title: LocalizedText.fromJson(json['title'] as Map<String, dynamic>),
        url: json['url'] as String?,
        status: _statusOf(json),
        description: _optionalText(json['description']),
        source: switch (json['provenance']) {
          {'source': final String s} => s,
          _ => null,
        },
        whereToFind: _optionalText(json['where_to_find']),
        searchQuery: json['search_query'] as String?,
        sourceLocation: switch (json['provenance']) {
          {'source_location': final String l} => l,
          _ => null,
        },
      );
}

LocalizedText? _optionalText(Object? v) => switch (v) {
      {'ar': final String ar, 'en': final String en} =>
        LocalizedText(ar: ar, en: en),
      _ => null,
    };

/// One student's answer to one question. [displayLanguage] is recorded for
/// transparency only; it never affects scoring.
class Response {
  const Response({
    required this.participantId,
    required this.questionId,
    required this.questionVersion,
    required this.selectedOptionId,
    required this.displayLanguage,
  });

  final String participantId;
  final String questionId;
  final int questionVersion;
  final String selectedOptionId;
  final Language displayLanguage;
}
