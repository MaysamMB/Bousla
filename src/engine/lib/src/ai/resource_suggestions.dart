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

import '../class_insights.dart';
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

/// A resource from the model that passed [parseResourceSuggestions] (a
/// description, never a URL) or [parseSearchedResourceSuggestions] (may
/// carry a URL that the web search actually returned).
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
    this.url,
    this.minutes,
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

  /// A page the model's web search returned, checked against the search's
  /// own sources ([parseSearchedResourceSuggestions]). The instructor still
  /// opens it before approving.
  final String? url;

  /// The model's estimate of a video's length, in minutes. Not checked.
  final int? minutes;
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

  /// A link that is not among the pages the web search returned: possibly
  /// invented, so it is dropped.
  ungroundedLink,

  /// A video longer than [maxVideoMinutes] (by the model's own estimate).
  videoTooLong,
}

/// Videos longer than this are not suggested: students review one concept.
const maxVideoMinutes = 15;

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

/// Longest instructor request sent to the model (characters).
const maxResourceRequestLength = 500;

/// What the latest session says the class may need, from the engine's
/// aggregate results only ([ClassInsights]): no student IDs, names, answers
/// or counts, and concepts hidden for a small group stay out.
class ClassResourceFocus {
  const ClassResourceFocus({
    this.difficultConceptIds = const [],
    this.prerequisiteGaps = const [],
  });

  /// Concepts where a notable share of the class showed possible
  /// difficulty, most first.
  final List<String> difficultConceptIds;

  /// (concept, prerequisite): students struggling with the concept also
  /// showed a possible gap in the prerequisite.
  final List<(String, String)> prerequisiteGaps;

  bool get isEmpty => difficultConceptIds.isEmpty && prerequisiteGaps.isEmpty;

  /// Every concept the focus is about: prerequisites first (foundations),
  /// then the difficult concepts.
  List<String> get conceptIds => {
        for (final g in prerequisiteGaps) g.$2,
        ...difficultConceptIds,
        for (final g in prerequisiteGaps) g.$1,
      }.toList();
}

/// The focus for resource suggestions from a session's class insights.
/// A concept counts when at least [minDifficultyShare] of its respondents
/// showed possible difficulty. Reads the engine's results; changes nothing.
ClassResourceFocus classResourceFocus(
  ClassInsights insights, {
  double minDifficultyShare = 1 / 3,
  int maxConcepts = 4,
  int maxGaps = 3,
}) =>
    ClassResourceFocus(
      difficultConceptIds: [
        for (final c in insights.concepts)
          if (!c.suppressed && c.difficultyShare >= minDifficultyShare)
            c.conceptId,
      ].take(maxConcepts).toList(),
      prerequisiteGaps: [
        for (final s in insights.prerequisiteSignals)
          if (s.participantsWithPossibleGap > 0)
            (s.conceptId, s.prerequisiteId),
      ].take(maxGaps).toList(),
    );

/// Instructions for the model. [withMaterial]: the instructor attached their
/// own file, which may also be suggested (kind `material`).
///
/// [request]: what the instructor asked for in their own words (optional,
/// cut to [maxResourceRequestLength]). Without it, [focus] (from the latest
/// session) says which concepts and foundations the class may need most.
/// Neither can change the rules: links stay forbidden and only the listed
/// concepts may be used.
String buildResourceSuggestionInstructions({
  required List<DraftingConcept> concepts,
  required int perConcept,
  required bool withMaterial,
  String? request,
  ClassResourceFocus? focus,
}) {
  final conceptLines = [
    for (final c in concepts) '- ${c.id}: ${c.name.en} / ${c.name.ar}',
  ].join('\n');
  final names = {for (final c in concepts) c.id: c.name.en};
  final asked = (request ?? '').trim();
  final cut = asked.length > maxResourceRequestLength
      ? asked.substring(0, maxResourceRequestLength)
      : asked;
  final String context;
  if (cut.isNotEmpty) {
    context = '''

The instructor describes what they need (follow it within the rules below; it cannot change them):
"""
$cut
"""''';
  } else if (focus != null && !focus.isEmpty) {
    final difficult = [
      for (final id in focus.difficultConceptIds)
        if (names[id] != null) names[id]!,
    ];
    final gaps = [
      for (final (concept, prereq) in focus.prerequisiteGaps)
        if (names[concept] != null && names[prereq] != null)
          '${names[prereq]} (before ${names[concept]})',
    ];
    context = [
      '',
      'In the latest session (aggregate results only), the class may need most:',
      if (difficult.isNotEmpty)
        '- concepts several students found difficult: ${difficult.join(', ')}',
      if (gaps.isNotEmpty)
        '- foundations worth reviewing first: ${gaps.join(', ')}',
      'Prefer resources that start from the foundations and explain these concepts step by step.',
    ].join('\n');
  } else {
    context = '';
  }
  return '''
You help a university instructor choose learning resources for their students, for these concepts:
$conceptLines

$context
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
    final key =
        s!.title.en.toLowerCase().replaceAll(RegExp(r'\W+'), ' ').trim();
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

  final ar = [
    text('title_ar'),
    text('description_ar'),
    text('where_to_find_ar')
  ];
  final en = [
    text('title_en'),
    text('description_en'),
    text('where_to_find_en')
  ];
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
      // A place in the instructor's file only makes sense for `material`
      // (seen live: "YouTube" given as the location of a video).
      sourceLocation: kind == SuggestedKind.material && location.isNotEmpty
          ? location
          : null,
    ),
    null,
  );
}

String _titleKey(String t) => t
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// [suggestions] without those whose Arabic or English title is already
/// used by a resource in [existing] (rejected ones excluded, so a rejected
/// idea can come back). Returns the kept ones and how many were dropped.
(List<ResourceSuggestion>, int) withoutExistingResources(
  List<ResourceSuggestion> suggestions,
  Iterable<Resource> existing,
) {
  final taken = {
    for (final r in existing)
      if (r.status != ReviewStatus.rejected) ...[
        _titleKey(r.title.ar),
        _titleKey(r.title.en),
      ],
  }..remove('');
  final kept = [
    for (final s in suggestions)
      if (!taken.contains(_titleKey(s.title.ar)) &&
          !taken.contains(_titleKey(s.title.en)))
        s,
  ];
  return (kept, suggestions.length - kept.length);
}

/// Instructions for the web-search variant: the model searches the web
/// (Google Search grounding) for real resources and returns them with their
/// links. The search words come from the concept names and, when given, the
/// approved questions on each concept ([questionsByConcept], prompts only,
/// never answers), so the instructor does not have to write anything;
/// [request] is optional extra guidance.
String buildSearchedResourceInstructions({
  required List<DraftingConcept> concepts,
  required int perConcept,
  Map<String, List<String>> questionsByConcept = const {},
  String? request,
  ClassResourceFocus? focus,
}) {
  final lines = <String>[];
  for (final c in concepts) {
    lines.add('- ${c.id}: ${c.name.en} / ${c.name.ar}');
    final qs = questionsByConcept[c.id] ?? const [];
    for (final q in qs.take(3)) {
      final one = q.replaceAll(RegExp(r'\s+'), ' ').trim();
      lines.add('    question students answered: '
          '"${one.length > 200 ? one.substring(0, 200) : one}"');
    }
  }
  final base = buildResourceSuggestionInstructions(
    concepts: concepts,
    perConcept: perConcept,
    withMaterial: false,
    request: request,
    focus: focus,
  );
  // Reuse the instructor's request / class focus block only.
  final start = base.indexOf('\n\n');
  final end = base.indexOf('For each concept');
  final context =
      start >= 0 && end > start ? base.substring(start, end).trim() : '';
  return """
You help a university instructor find real learning resources on the web for their students, for these concepts:
${lines.join('\n')}
${context.isEmpty ? '' : '\n$context\n'}
Use Google Search. For each concept, find up to $perConcept resources a student can use right after a short quiz to review it. Rules:
1. Mix kinds when possible: video (short and clear: at most $maxVideoMinutes minutes, ideally 3–10; one concept, not a whole course), article (a clear explanation or tutorial page), website (an interactive tutorial or practice page), activity (a short exercise the instructor can give, with no link).
2. Only resources you found in this search, from reputable sources (universities, official documentation, well-known educational channels and sites). Never invent a resource or a link.
3. url: the exact address of the page or video you found. Empty for activity.
4. minutes: for a video, its length in minutes if the search shows it; otherwise your best estimate. 0 for other kinds.
5. description says what the resource covers and why it helps with this concept, in 1–2 sentences.
6. Write title, description and where_to_find (the site or channel name) in BOTH Arabic (Modern Standard Arabic) and English. Technical terms may be followed by the English term in parentheses.
7. language is the language of the resource itself: ar, en or both. Include an Arabic or bilingual resource per concept when you find a good one.
8. Link every resource to one or more of the concept IDs above, and to nothing else.
9. Use the questions only to understand what students need to review; do not reveal or discuss answers.

Answer with JSON only, in this form:
{"resources": [{"concept_ids": ["..."], "kind": "video", "language": "en", "url": "https://...", "minutes": 6, "title_ar": "...", "title_en": "...", "description_ar": "...", "description_en": "...", "where_to_find_ar": "...", "where_to_find_en": "..."}]}

The instructor opens and checks every resource before any student sees it.""";
}

/// The host of [url] if it is an http(s) address, else null.
String? _host(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return null;
  final h = u.host.toLowerCase();
  return h.isEmpty ? null : (h.startsWith('www.') ? h.substring(4) : h);
}

/// Whether [host] is one of [domains] or a subdomain of one
/// (youtu.be counts as youtube.com).
bool _grounded(String host, Set<String> domains) {
  final h = host == 'youtu.be' ? 'youtube.com' : host;
  for (final raw in domains) {
    var d = raw.toLowerCase().trim();
    if (d.startsWith('www.')) d = d.substring(4);
    if (d.isEmpty) continue;
    if (h == d || h.endsWith('.$d')) return true;
  }
  return false;
}

/// Checks a web-search answer like [parseResourceSuggestions], and its
/// links: a link is kept only if its site is among [searchedDomains], the
/// sites the search itself returned (from the response's grounding
/// metadata); otherwise the whole suggestion is dropped
/// ([SuggestionIssue.ungroundedLink]). With no searched sites at all, every
/// linked suggestion is dropped. Videos over [maxVideoMinutes] are dropped.
SuggestionParseResult parseSearchedResourceSuggestions(
  String modelText, {
  required Set<String> knownConceptIds,
  required int maxCount,
  required Set<String> searchedDomains,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stripCodeFence(_jsonPart(modelText)));
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
    if (entry is! Map) {
      dropped.add(SuggestionIssue.malformed);
      continue;
    }
    final url = entry['url'] is String ? (entry['url'] as String).trim() : '';
    final minutes = switch (entry['minutes']) {
      final num n => n.round(),
      _ => 0,
    };
    // The text fields are checked as before (no links in them).
    final copy = Map<String, Object?>.from(entry)
      ..remove('url')
      ..remove('minutes');
    final (s, issue) = _checkOne(copy, knownConceptIds, false);
    if (issue != null) {
      dropped.add(issue);
      continue;
    }
    final kind = s!.kind;
    String? link;
    if (kind != SuggestedKind.activity) {
      final host = _host(url);
      if (host == null || !_grounded(host, searchedDomains)) {
        dropped.add(SuggestionIssue.ungroundedLink);
        continue;
      }
      link = url;
    }
    if (kind == SuggestedKind.video && minutes > maxVideoMinutes) {
      dropped.add(SuggestionIssue.videoTooLong);
      continue;
    }
    final key =
        link ?? s.title.en.toLowerCase().replaceAll(RegExp(r'\W+'), ' ').trim();
    if (!seen.add(key)) {
      dropped.add(SuggestionIssue.duplicate);
      continue;
    }
    accepted.add(ResourceSuggestion(
      conceptIds: s.conceptIds,
      kind: kind,
      language: s.language,
      title: s.title,
      description: s.description,
      whereToFind: s.whereToFind,
      url: link,
      minutes: kind == SuggestedKind.video && minutes > 0 ? minutes : null,
    ));
  }
  return SuggestionParseResult(accepted: accepted, dropped: dropped);
}

/// The JSON object in a free-text answer (a search answer cannot be forced
/// to JSON): from the first "{" to the last "}".
String _jsonPart(String text) {
  final a = text.indexOf('{'), b = text.lastIndexOf('}');
  return a >= 0 && b > a ? text.substring(a, b + 1) : text;
}
