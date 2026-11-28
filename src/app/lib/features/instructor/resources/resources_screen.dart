import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/open_link.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../content_review/generate_from_material.dart' show PickMaterial;
import '../course_picker.dart';
import 'resource_editor.dart';
import 'suggest_resources_dialog.dart';

/// Learning resources students get as next steps in their feedback
/// (docs/architecture.md §4). The instructor:
///
/// - adds a resource: a title in any language, a link, its kind, its
///   language and the concepts it helps with; it is approved at once;
/// - asks AI to describe resources to look for (kind, where to look,
///   search words, what it should cover). The model never gives links: the
///   instructor finds the real resource, adds its link and approves it, or
///   rejects the suggestion;
/// - edits, removes or restores resources.
///
/// Students only ever receive approved resources (the engine's recommender
/// and the security rules both check it).
class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key, this.pickMaterial});

  /// File picker for the optional material; replaced in tests.
  final PickMaterial? pickMaterial;

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _Data {
  const _Data({
    required this.course,
    required this.courses,
    required this.concepts,
    required this.resources,
  });

  final Course course;
  final List<Course> courses;
  final List<Concept> concepts;
  final List<Resource> resources;

  List<Concept> get approvedConcepts =>
      concepts.where((c) => c.status == ReviewStatus.approved).toList();

  List<Resource> withStatus(ReviewStatus s) =>
      resources.where((r) => r.status == s).toList();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  Future<_Data?>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_Data?> _load() async {
    final services = ServicesScope.of(context);
    final repo = services.content;
    final courses = await repo.listCourses();
    final course = chooseCourse(courses, services.selectedCourseId.value);
    if (course == null) return null;
    return _Data(
      course: course,
      courses: courses,
      concepts: await repo.listConcepts(course.id),
      resources: await repo.listResources(course.id, approvedOnly: false),
    );
  }

  // A block body: setState must not get a Future back.
  void _reload() => setState(() {
        _data = _load();
      });

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit(_Data data, [Resource? resource]) async {
    final l = AppLocalizations.of(context);
    final saved = await showDialog<Resource>(
      context: context,
      builder: (_) => ResourceEditor(
        courseId: data.course.id,
        concepts: data.approvedConcepts,
        resource: resource,
      ),
    );
    if (saved == null || !mounted) return;
    _message(l.instructorResSaved);
    _reload();
  }

  Future<void> _setStatus(_Data data, Resource r, ReviewStatus status) async {
    await ServicesScope.of(context)
        .content
        .setResourcesStatus(data.course.id, [r.id], status);
    if (mounted) _reload();
  }

  Future<void> _suggest(_Data data) async {
    final summary = await showDialog<String>(
      context: context,
      builder: (_) => SuggestResourcesDialog(
        courseId: data.course.id,
        concepts: data.approvedConcepts,
        pickMaterial: widget.pickMaterial,
      ),
    );
    if (summary == null || !mounted) return;
    _message(summary);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final suggester = ServicesScope.of(context).resourceSuggester;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.instructorResTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: FutureBuilder<_Data?>(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (snapshot.hasError) return Center(child: Text(l.errorGeneric));
          if (data == null) {
            return Center(
              child: snapshot.connectionState == ConnectionState.done
                  ? Text(l.instructorNoCourse)
                  : const CircularProgressIndicator(),
            );
          }
          final pending = data.withStatus(ReviewStatus.pendingReview);
          final approved = data.withStatus(ReviewStatus.approved);
          final rejected = data.withStatus(ReviewStatus.rejected);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              CoursePicker(
                courses: data.courses,
                current: data.course,
                onChanged: _reload,
              ),
              const SizedBox(height: 8),
              Text(
                l.instructorResNotice,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (suggester != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: data.approvedConcepts.isEmpty
                        ? null
                        : () => _suggest(data),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(l.instructorResSuggest),
                  ),
                ),
              ],
              if (pending.isNotEmpty) ...[
                _Heading(l.instructorResPending(pending.length)),
                for (final r in pending)
                  _ResourceCard(
                    resource: r,
                    concepts: data.concepts,
                    actions: [
                      TextButton(
                        onPressed: () =>
                            _setStatus(data, r, ReviewStatus.rejected),
                        child: Text(l.reviewReject),
                      ),
                      // Found by the web search: open it, then approve (or
                      // edit). Otherwise the instructor adds the link.
                      if (r.url != null) ...[
                        OutlinedButton(
                          onPressed: () => _edit(data, r),
                          child: Text(l.reviewEdit),
                        ),
                        FilledButton.icon(
                          key: ValueKey('approve-${r.id}'),
                          onPressed: () =>
                              _setStatus(data, r, ReviewStatus.approved),
                          icon: const Icon(Icons.check),
                          label: Text(l.reviewApprove),
                        ),
                      ] else
                        FilledButton.icon(
                          onPressed: () => _edit(data, r),
                          icon: const Icon(Icons.add_link),
                          label: Text(l.instructorResAddLink),
                        ),
                    ],
                  ),
              ],
              _Heading(l.instructorResApproved(approved.length)),
              if (approved.isEmpty)
                Text(l.instructorResNone)
              else
                for (final r in approved)
                  _ResourceCard(
                    resource: r,
                    concepts: data.concepts,
                    actions: [
                      TextButton(
                        onPressed: () =>
                            _setStatus(data, r, ReviewStatus.rejected),
                        child: Text(l.instructorResRemove),
                      ),
                      OutlinedButton(
                        onPressed: () => _edit(data, r),
                        child: Text(l.reviewEdit),
                      ),
                    ],
                  ),
              if (rejected.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l.instructorResRejected(rejected.length)),
                  children: [
                    for (final r in rejected)
                      _ResourceCard(
                        resource: r,
                        concepts: data.concepts,
                        actions: [
                          TextButton(
                            onPressed: () => _setStatus(
                              data,
                              r,
                              r.url == null && r.source == 'ai_draft'
                                  ? ReviewStatus.pendingReview
                                  : ReviewStatus.approved,
                            ),
                            child: Text(l.reviewRestore),
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<_Data?>(
        future: _data,
        builder: (context, snapshot) => snapshot.data == null
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => _edit(snapshot.data!),
                icon: const Icon(Icons.add),
                label: Text(l.instructorResAdd),
              ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

String resourceTypeText(AppLocalizations l, ResourceType t) => switch (t) {
      ResourceType.video => l.instructorResTypeVideo,
      ResourceType.link => l.instructorResTypeLink,
      ResourceType.file => l.instructorResTypeFile,
      ResourceType.activity => l.instructorResTypeActivity,
    };

String resourceLanguageText(AppLocalizations l, ResourceLanguage lang) =>
    switch (lang) {
      ResourceLanguage.ar => l.instructorResLangAr,
      ResourceLanguage.en => l.instructorResLangEn,
      ResourceLanguage.both => l.instructorResLangBoth,
    };

IconData _icon(ResourceType t) => switch (t) {
      ResourceType.video => Icons.smart_display_outlined,
      ResourceType.link => Icons.link,
      ResourceType.file => Icons.description_outlined,
      ResourceType.activity => Icons.edit_note,
    };

/// A search page for the AI's search words: YouTube for videos, otherwise a
/// general search engine.
String searchUrl(ResourceType type, String query) {
  final q = Uri.encodeQueryComponent(query);
  return type == ResourceType.video
      ? 'https://www.youtube.com/results?search_query=$q'
      : 'https://www.google.com/search?q=$q';
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.concepts,
    required this.actions,
  });

  final Resource resource;
  final List<Concept> concepts;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    final theme = Theme.of(context);
    final r = resource;
    final names = [
      for (final id in r.conceptIds)
        concepts.where((c) => c.id == id).firstOrNull?.name.of(lang) ?? id,
    ];
    final small = theme.textTheme.bodySmall;
    return Card(
      key: ValueKey('resource-${r.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(r.type), color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.title.of(lang),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                resourceTypeText(l, r.type),
                resourceLanguageText(l, r.language),
                if (r.source == 'ai_draft') l.instructorResFromAi,
              ].join(' · '),
              style: small,
            ),
            Text(l.instructorResConcepts(names.join('، ')), style: small),
            if (r.description case final d?) ...[
              const SizedBox(height: 8),
              Text(d.of(lang)),
            ],
            if (r.url case final url?) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => openLink(url),
                child: Text(
                  url,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ] else if (r.status == ReviewStatus.pendingReview) ...[
              if (r.whereToFind case final w?) ...[
                const SizedBox(height: 8),
                Text(l.instructorResWhere(w.of(lang))),
              ],
              if (r.sourceLocation case final loc?)
                Text(l.instructorResLocation(loc), style: small),
              if (r.searchQuery case final q?) ...[
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(l.instructorResSearchWords),
                    // Search words may be English inside Arabic text.
                    SelectableText(
                      q,
                      textDirection: RegExp(r'[؀-ۿ]').hasMatch(q)
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextButton.icon(
                      onPressed: () => openLink(searchUrl(r.type, q)),
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(l.instructorResSearch),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
