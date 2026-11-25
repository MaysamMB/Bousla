import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import 'resource_editor.dart';

/// Before feedback is published (session open, or closed and not yet
/// published): the concepts this session's questions test, with how many
/// approved resources each has. Feedback is built at publish time from the
/// course's approved resources, so a resource added here still reaches the
/// students of this session. Concepts with none are listed first and can get
/// one at once ("Add resource", the concept already chosen).
class SessionResourcesCard extends StatefulWidget {
  const SessionResourcesCard({super.key, required this.session});

  final Session session;

  @override
  State<SessionResourcesCard> createState() => _SessionResourcesCardState();
}

class _ConceptRow {
  const _ConceptRow(this.concept, this.approved, this.waiting);

  final Concept concept;
  final int approved;

  /// AI suggestions for it still waiting for a link.
  final int waiting;
}

class _SessionResourcesCardState extends State<SessionResourcesCard> {
  Future<List<_ConceptRow>>? _rows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rows ??= _load();
  }

  Future<List<_ConceptRow>> _load() async {
    final content = ServicesScope.of(context).content;
    final courseId = widget.session.courseId;
    final questions = await content.questionsForSession(
      courseId,
      widget.session.questions,
    );
    final covered = {
      for (final q in questions) ...q.question.conceptIds,
    };
    final concepts = await content.listConcepts(courseId);
    final resources = await content.listResources(
      courseId,
      approvedOnly: false,
    );
    int count(String id, ReviewStatus s) => resources
        .where((r) => r.status == s && r.conceptIds.contains(id))
        .length;
    final rows = [
      for (final c in concepts)
        if (covered.contains(c.id))
          _ConceptRow(
            c,
            count(c.id, ReviewStatus.approved),
            count(c.id, ReviewStatus.pendingReview),
          ),
    ];
    // Missing first, then by name order of the course.
    rows.sort((a, b) => (a.approved == 0 ? 0 : 1)
        .compareTo(b.approved == 0 ? 0 : 1));
    return rows;
  }

  // A block body: setState must not get a Future back.
  void _reload() => setState(() {
        _rows = _load();
      });

  Future<void> _add(List<Concept> approvedConcepts, Concept concept) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<Resource>(
      context: context,
      builder: (_) => ResourceEditor(
        courseId: widget.session.courseId,
        concepts: approvedConcepts,
        initialConceptIds: [concept.id],
      ),
    );
    if (saved == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.instructorResSaved)));
    _reload();
  }

  Future<void> _openAll() async {
    await Navigator.of(context).pushNamed('/instructor/resources');
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<_ConceptRow>>(
          future: _rows,
          builder: (context, snapshot) {
            final rows = snapshot.data;
            if (rows == null) {
              return snapshot.hasError
                  ? Text(l.errorGeneric)
                  : const Center(child: CircularProgressIndicator());
            }
            final missing = rows.where((r) => r.approved == 0).length;
            final approvedConcepts = [
              for (final r in rows)
                if (r.concept.status == ReviewStatus.approved) r.concept,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.instructorSessionResTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  missing == 0
                      ? l.instructorSessionResAllCovered
                      : l.instructorSessionResMissing(missing),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final r in rows)
                  ListTile(
                    key: ValueKey('session-res-${r.concept.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.approved == 0
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: r.approved == 0
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                    title: Text(r.concept.name.of(lang)),
                    subtitle: Text(
                      [
                        l.instructorSessionResCount(r.approved),
                        if (r.waiting > 0) l.instructorSessionResWaiting(r.waiting),
                      ].join(' · '),
                    ),
                    trailing: r.concept.status == ReviewStatus.approved
                        ? TextButton.icon(
                            onPressed: () => _add(approvedConcepts, r.concept),
                            icon: const Icon(Icons.add),
                            label: Text(l.instructorResAdd),
                          )
                        : null,
                  ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: _openAll,
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text(l.instructorSessionResAll),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
