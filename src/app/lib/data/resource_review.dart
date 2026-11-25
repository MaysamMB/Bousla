import 'package:bousla_engine/bousla_engine.dart';

/// What the instructor fills in for a resource (docs/architecture.md §4).
/// The title is one text box in any language: [titleText]. When the
/// resource came from an AI suggestion and the title was not changed,
/// [keepTitle] carries the original bilingual title.
class ResourceDraft {
  const ResourceDraft({
    this.id,
    required this.conceptIds,
    required this.type,
    required this.language,
    required this.titleText,
    this.url,
    this.keepTitle,
  });

  /// Null for a new resource.
  final String? id;
  final List<String> conceptIds;
  final ResourceType type;
  final ResourceLanguage language;
  final String titleText;
  final String? url;
  final LocalizedText? keepTitle;

  LocalizedText get title {
    final t = titleText.trim();
    return keepTitle ?? LocalizedText(ar: t, en: t);
  }
}

enum ResourceDraftIssue {
  noConcept,
  titleMissing,
  urlMissing,
  urlInvalid,

  /// Another resource of the course already has this link.
  duplicateLink,
}

/// Activities may have no link; videos, links and files need an http(s)
/// link the instructor checked. With [existing] (the course's resources),
/// a link already used by another resource is refused; rejected ones do
/// not count.
List<ResourceDraftIssue> validateResourceDraft(
  ResourceDraft d,
  Set<String> approvedConceptIds, {
  Iterable<Resource> existing = const [],
}) {
  final url = d.url?.trim() ?? '';
  final valid = url.isNotEmpty && isWebLink(url);
  return [
    if (!d.conceptIds.any(approvedConceptIds.contains))
      ResourceDraftIssue.noConcept,
    if (d.titleText.trim().isEmpty) ResourceDraftIssue.titleMissing,
    if (url.isEmpty && d.type != ResourceType.activity)
      ResourceDraftIssue.urlMissing,
    if (url.isNotEmpty && !isWebLink(url)) ResourceDraftIssue.urlInvalid,
    if (valid &&
        existing.any(
          (r) =>
              r.id != d.id &&
              r.status != ReviewStatus.rejected &&
              r.url != null &&
              sameWebLink(r.url!, url),
        ))
      ResourceDraftIssue.duplicateLink,
  ];
}

/// The same page, ignoring http/https, "www.", letter case of the host and
/// a trailing slash.
bool sameWebLink(String a, String b) {
  String key(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return url.trim();
    final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final path = u.path.replaceFirst(RegExp(r'/+$'), '');
    return '$host$path${u.hasQuery ? '?${u.query}' : ''}';
  }

  return key(a) == key(b);
}

bool isWebLink(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null &&
      (u.scheme == 'https' || u.scheme == 'http') &&
      u.host.contains('.');
}

/// "عربي" titles → ar, others → en; the instructor can change it.
ResourceLanguage guessResourceLanguage(String text) =>
    RegExp(r'[؀-ۿ]').hasMatch(text) ? ResourceLanguage.ar : ResourceLanguage.en;

/// The saved resource: approved (the instructor wrote or checked it). An
/// edited AI suggestion keeps `source: ai_draft`, its description and brief.
Resource resourceFromDraft(
  ResourceDraft d, {
  required String id,
  Resource? before,
}) =>
    Resource(
      id: id,
      conceptIds: d.conceptIds,
      type: d.type,
      language: d.language,
      title: d.title,
      url: (d.url?.trim().isEmpty ?? true) ? null : d.url!.trim(),
      status: ReviewStatus.approved,
      description: before?.description,
      source: before?.source ?? 'instructor',
      whereToFind: before?.whereToFind,
      searchQuery: before?.searchQuery,
      sourceLocation: before?.sourceLocation,
    );

/// A model suggestion as a pending resource with no link.
Resource resourceFromSuggestion(ResourceSuggestion s, {required String id}) =>
    Resource(
      id: id,
      conceptIds: s.conceptIds,
      type: s.kind.resourceType,
      language: s.language,
      title: s.title,
      status: ReviewStatus.pendingReview,
      description: s.description,
      source: 'ai_draft',
      whereToFind: s.whereToFind,
      searchQuery: s.searchQuery,
      sourceLocation: s.sourceLocation,
    );

Resource withResourceStatus(Resource r, ReviewStatus status) => Resource(
      id: r.id,
      conceptIds: r.conceptIds,
      type: r.type,
      language: r.language,
      title: r.title,
      url: r.url,
      status: status,
      description: r.description,
      source: r.source,
      whereToFind: r.whereToFind,
      searchQuery: r.searchQuery,
      sourceLocation: r.sourceLocation,
    );

Map<String, dynamic>? _text(LocalizedText? t) =>
    t == null ? null : {'ar': t.ar, 'en': t.en};

String _status(ReviewStatus s) => switch (s) {
      ReviewStatus.pendingReview => 'pending_review',
      ReviewStatus.approved => 'approved',
      ReviewStatus.rejected => 'rejected',
    };

/// Same layout as `data/courses/*/resources.json`, read back by
/// [Resource.fromJson].
Map<String, dynamic> resourceToJson(
  Resource r, {
  String? reviewedBy,
  String? generatedBy,
}) =>
    {
      'id': r.id,
      'concept_ids': r.conceptIds,
      'type': r.type.name,
      'language': r.language.name,
      'title': _text(r.title),
      'description': _text(r.description),
      'url': r.url,
      'where_to_find': _text(r.whereToFind),
      'search_query': r.searchQuery,
      'provenance': {
        'source': r.source ?? 'instructor',
        'status': _status(r.status),
        'reviewed_by': reviewedBy,
        'source_location': r.sourceLocation,
        if (generatedBy != null) 'generated_by': generatedBy,
      },
    };
