/// AI level 1, resources: the model describes learning resources the
/// instructor could add for each concept (what kind, where to look, what it
/// should cover). It never gives links: models invent URLs that do not
/// exist. The instructor finds the real resource, adds its link and
/// approves it; until then students see nothing of it.
///
/// No network code here: instructions, JSON schema and the checks on the
/// model's answer, so they can be tested without Gemini.
library;

import 'dart:convert';

import '../models.dart';
import 'model_json.dart';
import 'question_drafting.dart' show DraftingConcept;

/// What kind of resource the model suggests. Mapped to [ResourceType] when
/// saved: video → video, article and website → link, activity → activity,
/// material (a part of the instructor's own file) → file.
enum SuggestedKind {
  video,
  article,
  website,
  activity,
  material;

  ResourceType get resourceType => switch (this) {
        SuggestedKind.video => ResourceType.video,
        SuggestedKind.article || SuggestedKind.website => ResourceType.link,
        SuggestedKind.activity => ResourceType.activity,
        SuggestedKind.material => ResourceType.file,
      };

  static SuggestedKind? tryParse(String? value) {
    for (final k in SuggestedKind.values) {
      if (k.name == value) return k;
    }
    return null;
  }
}

/// A resource description from the model that passed
/// [parseResourceSuggestions]. Never has a URL.
class ResourceSuggestion {
  const ResourceSuggestion({
    required this.conceptIds,
    required this.kind,
    required this.language,
    required this.title,
    required this.description,
    required this.whereToFind,
    this.searchQuery,
    this.sourceLocation,
  });

  final List<String> conceptIds;
  final SuggestedKind kind;

  /// Language the resource should be in.
  final ResourceLanguage language;
  final LocalizedText title;

  /// What the resource should cover, and why it helps with the concept.
  final LocalizedText description;

  /// Where to look, e.g. "YouTube, a university channel" or "your lecture,
  /// page 12".
  final LocalizedText whereToFind;

  /// Words to search for, in the resource's language. Null for activities
  /// and the instructor's own material.
  final String? searchQuery;

  /// Where in the instructor's material, when one was attached.
  final String? sourceLocation;
}

/// Why a suggestion was dropped before reaching the instructor.
enum SuggestionIssue {
  invalidJson,
  malformed,
  unknownConcept,
  unknownKind,
  arabicMissing,
  englishMissing,

  /// The model wrote a link (http…, www…, a domain): links are found and
  /// checked by the instructor, never taken from the model.
  containsLink,
  duplicate,
}

class SuggestionParseResult {
  const SuggestionParseResult({required this.accepted, required this.dropped});

  final List<ResourceSuggestion> accepted;
  final List<SuggestionIssue> dropped;
}

final _arabicLetter = RegExp(r'[؀-ۿ]');

/// http(s)://, www., or a word followed by a common domain ending
/// (youtube.com, w3schools.com/sql, khanacademy.org …). Names without a
/// domain ("YouTube", "Khan Academy") are fine.
final _link = RegExp(
  r'https?://|www\.|\b[\w-]+\.(com|org|net|edu|io|gov|info|me|ly|be|co|ac)\b',
  caseSensitive: false,
);

bool containsLink(String text) => _link.hasMatch(text);

/// Instructions for the model. [withMaterial]: the instructor attached their
/// own file, which may also be suggested (kind `material`).
String buildResourceSuggestionInstructions({
  required List<DraftingConcept> concepts,
  required int perConcept,
  required bool withMaterial,
}) {
  final conceptLines = [
    for (final c in concepts) '- ${c.id}: ${c.name.en} / ${c.name.ar}',
  ].join('\n');
  return '''
You help a university instructor choose learning resources for their students, for these concepts:
$conceptLines

For each concept, suggest up to $perConcept resources a student could use after a short quiz to review it. You do NOT give links: describe each resource so the instructor can find a real one quickly and check it. Rules:
1. kind is one of: video, article, website, activity${withMaterial ? ', material' : ''}.
   - video, article, website: a kind of resource that is commonly available. In where_to_find, name the kind of place to look (for example "YouTube, an introductory database course from a university channel", "the PostgreSQL documentation"). Never write a URL, a domain name or a web address.
   - activity: a short exercise the instructor can give (for example "design two tables and mark the primary and foreign keys"). Describe it fully in description.${withMaterial ? '''
   - material: a part of the attached course material that explains the concept well. source_location says where, for example "page 12" or "section 2.1".''' : ''}
2. search_query: words the instructor can type into a search engine or YouTube to find it, in the resource's language. Empty for activity${withMaterial ? ' and material' : ''}.
3. description says what the resource must cover and why it helps with this concept, in 1–2 sentences.
4. Write title, description and where_to_find in BOTH Arabic (Modern Standard Arabic) and English. Technical terms may be followed by the English term in parentheses.
5. language is the language the resource itself should be in: ar, en or both. Prefer at least one Arabic or bilingual resource per concept when that is realistic.
6. Link every suggestion to one or more of the concept IDs above, and to nothing else.

These are suggestions. The instructor finds and checks every resource before any student sees it.''';
}

Map<String, Object?> resourceSuggestionJsonSchema() => {
      'type': 'object',
      'properties': {
        'resources': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'concept_ids': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'kind': {
                'type': 'string',
                'enum': [for (final k in SuggestedKind.values) k.name],
              },
              'language': {
                'type': 'string',
                'enum': ['ar', 'en', 'both'],
              },
              'title_ar': {'type': 'string'},
              'title_en': {'type': 'string'},
              'description_ar': {'type': 'string'},
              'description_en': {'type': 'string'},
              'where_to_find_ar': {'type': 'string'},
              'where_to_find_en': {'type': 'string'},
              'search_query': {'type': 'string'},
              'source_location': {'type': 'string'},
            },
            'required': [
              'concept_ids',
              'kind',
              'language',
              'title_ar',
              'title_en',
              'description_ar',
              'description_en',
              'where_to_find_ar',
              'where_to_find_en',
            ],
          },
        },
      },
      'required': ['resources'],
    };

/// Checks the model's answer; at most [maxCount] suggestions are accepted.
/// [allowMaterial]: kind `material` only when a file was attached.
SuggestionParseResult parseResourceSuggestions(
  String modelText, {
  required Set<String> knownConceptIds,
  required int maxCount,
  bool allowMaterial = false,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stripCodeFence(modelText));
  } on FormatException {
    return const SuggestionParseResult(
      accepted: [],
      dropped: [SuggestionIssue.invalidJson],
    );
  }
  final list = switch (decoded) {
    {'resources': final List<Object?> r} => r,
    final List<Object?> r => r,
    _ => null,
  };
  if (list == null) {
    return const SuggestionParseResult(
      accepted: [],
      dropped: [SuggestionIssue.invalidJson],
    );
  }
  final accepted = <ResourceSuggestion>[];
  final dropped = <SuggestionIssue>[];
  final seen = <String>{};
  for (final entry in list) {
    if (accepted.length >= maxCount) break;
    final (s, issue) = _checkOne(entry, knownConceptIds, allowMaterial);
    if (issue != null) {
      dropped.add(issue);
      continue;
    }
    final key = s!.title.en.toLowerCase().replaceAll(RegExp(r'\W+'), ' ').trim();
    if (!seen.add(key)) {
      dropped.add(SuggestionIssue.duplicate);
      continue;
    }
    accepted.add(s);
  }
  return SuggestionParseResult(accepted: accepted, dropped: dropped);
}

(ResourceSuggestion?, SuggestionIssue?) _checkOne(
  Object? entry,
  Set<String> known,
  bool allowMaterial,
) {
  if (entry is! Map) return (null, SuggestionIssue.malformed);
  String text(String key) {
    final v = entry[key];
    return v is String ? v.trim() : '';
  }

  final rawConcepts = entry['concept_ids'];
  if (rawConcepts is! List) return (null, SuggestionIssue.malformed);
  final conceptIds = [
    for (final c in rawConcepts)
      if (c is String && known.contains(c.trim())) c.trim(),
  ].toSet().toList();
  if (conceptIds.isEmpty) return (null, SuggestionIssue.unknownConcept);

  final kind = SuggestedKind.tryParse(text('kind'));
  if (kind == null || (kind == SuggestedKind.material && !allowMaterial)) {
    return (null, SuggestionIssue.unknownKind);
  }
  final language = switch (text('language')) {
    'ar' => ResourceLanguage.ar,
    'en' => ResourceLanguage.en,
    _ => ResourceLanguage.both,
  };

  final ar = [text('title_ar'), text('description_ar'), text('where_to_find_ar')];
  final en = [text('title_en'), text('description_en'), text('where_to_find_en')];
  if (ar.any((t) => t.isEmpty || !_arabicLetter.hasMatch(t))) {
    return (null, SuggestionIssue.arabicMissing);
  }
  if (en.any((t) => t.isEmpty)) return (null, SuggestionIssue.englishMissing);

  final query = text('search_query');
  final location = text('source_location');
  if ([...ar, ...en, query, location].any(containsLink)) {
    return (null, SuggestionIssue.containsLink);
  }
  final noSearch =
      kind == SuggestedKind.activity || kind == SuggestedKind.material;
  return (
    ResourceSuggestion(
      conceptIds: conceptIds,
      kind: kind,
      language: language,
      title: LocalizedText(ar: ar[0], en: en[0]),
      description: LocalizedText(ar: ar[1], en: en[1]),
      whereToFind: LocalizedText(ar: ar[2], en: en[2]),
      searchQuery: noSearch || query.isEmpty ? null : query,
      sourceLocation: location.isEmpty ? null : location,
    ),
    null,
  );
}
