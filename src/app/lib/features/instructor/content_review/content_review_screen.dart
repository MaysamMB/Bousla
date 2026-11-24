import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../data/question_review.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'question_editor_screen.dart';
import 'review_texts.dart';

/// Instructor reviews questions before students can see them (owner: AI and
/// content). See docs/architecture.md §4.
///
/// - Waiting: approve, edit or reject one question; select several to
///   approve or reject together; reject everything waiting at once.
/// - Approved: edit (creates a new version) or take back to review.
/// - Rejected: edit or take back to review. Rejected questions are kept, not
///   deleted, so decisions can be undone and counted.
/// - Add a question by hand.
///
/// There is deliberately no "approve all" button: every AI draft is seen by
/// the instructor before it is approved.
class ContentReviewScreen extends StatefulWidget {
  const ContentReviewScreen({super.key});

  @override
  State<ContentReviewScreen> createState() => _ContentReviewScreenState();
}

class _ReviewData {
  const _ReviewData({
    required this.course,
    required this.concepts,
    required this.questions,
    required this.keys,
  });

  final Course course;
  final List<Concept> concepts;

  /// Latest version of every question, any status.
  final List<QuestionView> questions;
  final List<AnswerKey> keys;

  List<QuestionView> withStatus(ReviewStatus status) =>
      questions.where((q) => q.status == status).toList();

  String? keyFor(QuestionView q) => keys
      .where((k) => k.questionId == q.id && k.questionVersion == q.version)
      .firstOrNull
      ?.correctOptionId;

  List<Concept> get approvedConcepts =>
      concepts.where((c) => c.status == ReviewStatus.approved).toList();
}

class _ContentReviewScreenState extends State<ContentReviewScreen> {
  Future<_ReviewData>? _data;
  final _selected = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_ReviewData> _load() async {
    final repo = ServicesScope.of(context).content;
    final course = (await repo.listCourses()).first;
    final concepts = await repo.listConcepts(course.id);
    final questions = await repo.listQuestions(course.id, approvedOnly: false);
    final keys = await repo.answerKeys(course.id);
    return _ReviewData(
      course: course,
      concepts: concepts,
      questions: questions,
      keys: keys,
    );
  }

  void _reload() => setState(() {
    _selected.clear();
    _data = _load();
  });

  Future<void> _setStatus(
    String courseId,
    List<String> ids,
    ReviewStatus status, {
    RejectionReason? reason,
  }) async {
    if (ids.isEmpty) return;
    await ServicesScope.of(
      context,
    ).content.setQuestionsStatus(courseId, ids, status, reason: reason);
    if (mounted) _reload();
  }

  Future<void> _reject(String courseId, List<String> ids) async {
    if (ids.isEmpty) return;
    final choice = await showDialog<_RejectChoice>(
      context: context,
      builder: (_) => _RejectDialog(count: ids.length),
    );
    if (choice == null || !mounted) return;
    await _setStatus(
      courseId,
      ids,
      ReviewStatus.rejected,
      reason: choice.reason,
    );
  }

  Future<void> _openEditor(_ReviewData data, [QuestionView? question]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuestionEditorScreen(
          courseId: data.course.id,
          concepts: data.approvedConcepts,
          question: question,
          correctOptionId: question == null ? null : data.keyFor(question),
        ),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<_ReviewData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(l.reviewTitle)),
            body: Center(
              child: snapshot.hasError
                  ? Text(l.errorGeneric)
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final data = snapshot.data!;
        final pending = data.withStatus(ReviewStatus.pendingReview);
        final approved = data.withStatus(ReviewStatus.approved);
        final rejected = data.withStatus(ReviewStatus.rejected);
        final courseId = data.course.id;
        final selected = pending
            .where((q) => _selected.contains(q.id))
            .map((q) => q.id)
            .toList();

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.reviewTitle),
              actions: const [LanguageSwitcher()],
              bottom: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: l.reviewTabPending(pending.length)),
                  Tab(text: l.reviewTabApproved(approved.length)),
                  Tab(text: l.reviewTabRejected(rejected.length)),
                ],
              ),
            ),
            body: Column(
              children: [
                _StatsBanner(stats: aiReviewStats(data.questions)),
                Expanded(
                  child: TabBarView(
                    children: [
                      _QuestionList(
                        data: data,
                        questions: pending,
                        header: pending.isEmpty
                            ? null
                            : Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  onPressed: () => _reject(courseId, [
                                    for (final q in pending) q.id,
                                  ]),
                                  icon: const Icon(Icons.block),
                                  label: Text(l.reviewRejectAllPending),
                                ),
                              ),
                        isSelected: (q) => _selected.contains(q.id),
                        onSelected: (q, value) => setState(
                          () => value
                              ? _selected.add(q.id)
                              : _selected.remove(q.id),
                        ),
                        actions: (q) => [
                          TextButton(
                            onPressed: () => _reject(courseId, [q.id]),
                            child: Text(l.reviewReject),
                          ),
                          OutlinedButton(
                            onPressed: () => _openEditor(data, q),
                            child: Text(l.reviewEdit),
                          ),
                          FilledButton(
                            onPressed: () => _setStatus(courseId, [
                              q.id,
                            ], ReviewStatus.approved),
                            child: Text(l.reviewApprove),
                          ),
                        ],
                      ),
                      _QuestionList(
                        data: data,
                        questions: approved,
                        actions: (q) => [
                          TextButton(
                            onPressed: () => _setStatus(courseId, [
                              q.id,
                            ], ReviewStatus.pendingReview),
                            child: Text(l.reviewRestore),
                          ),
                          OutlinedButton(
                            onPressed: () => _openEditor(data, q),
                            child: Text(l.reviewEdit),
                          ),
                        ],
                      ),
                      _QuestionList(
                        data: data,
                        questions: rejected,
                        actions: (q) => [
                          OutlinedButton(
                            onPressed: () => _openEditor(data, q),
                            child: Text(l.reviewEdit),
                          ),
                          TextButton(
                            onPressed: () => _setStatus(courseId, [
                              q.id,
                            ], ReviewStatus.pendingReview),
                            child: Text(l.reviewRestore),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: selected.isEmpty
                ? FloatingActionButton.extended(
                    onPressed: () => _openEditor(data),
                    icon: const Icon(Icons.add),
                    label: Text(l.reviewAddQuestion),
                  )
                : null,
            bottomNavigationBar: selected.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _reject(courseId, selected),
                            child: Text(
                              l.reviewRejectSelected(selected.length),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => _setStatus(
                              courseId,
                              selected,
                              ReviewStatus.approved,
                            ),
                            child: Text(
                              l.reviewApproveSelected(selected.length),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.stats});

  final AiReviewStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.reviewAiNotice, style: theme.textTheme.bodyMedium),
          if (stats.total > 0) ...[
            const SizedBox(height: 4),
            Text(
              l.reviewStats(
                stats.total,
                stats.approvedAsIs,
                stats.approvedEdited,
                stats.rejected,
                stats.pending,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionList extends StatelessWidget {
  const _QuestionList({
    required this.data,
    required this.questions,
    required this.actions,
    this.header,
    this.isSelected,
    this.onSelected,
  });

  final _ReviewData data;
  final List<QuestionView> questions;
  final List<Widget> Function(QuestionView) actions;
  final Widget? header;
  final bool Function(QuestionView)? isSelected;
  final void Function(QuestionView, bool)? onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (questions.isEmpty) return Center(child: Text(l.reviewEmpty));
    final onSelected = this.onSelected;
    final header = this.header;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (header != null) header,
        for (final q in questions)
          _QuestionCard(
            question: q,
            concepts: data.concepts,
            correctOptionId: data.keyFor(q),
            selected: isSelected?.call(q),
            onSelected: onSelected == null
                ? null
                : (value) => onSelected(q, value),
            actions: actions(q),
          ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.concepts,
    required this.correctOptionId,
    required this.actions,
    this.selected,
    this.onSelected,
  });

  final QuestionView question;
  final List<Concept> concepts;
  final String? correctOptionId;
  final List<Widget> actions;
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = currentLanguage(context);
    final onSelected = this.onSelected;
    final conceptNames = [
      for (final id in question.conceptIds)
        concepts.where((c) => c.id == id).firstOrNull?.name.of(language) ?? id,
    ];
    final reason = question.rejectionReason;
    final location = question.sourceLocation;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onSelected != null)
                  Checkbox(
                    value: selected ?? false,
                    onChanged: (value) => onSelected(value ?? false),
                  ),
                Expanded(
                  child: Text(
                    question.prompt.of(language),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final option in question.options)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      option.id == correctOptionId
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: option.id == correctOptionId
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      semanticLabel: option.id == correctOptionId
                          ? l.reviewCorrectAnswer
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(option.text.of(language))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in conceptNames) _Tag(name),
                _Tag(sourceText(l, question.source)),
                if (question.edited) _Tag(l.reviewEdited),
                _Tag(l.reviewVersion(question.version)),
              ],
            ),
            if (location != null) ...[
              const SizedBox(height: 4),
              Text(
                l.reviewSourceLocation(location),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: 4),
              Text(
                l.reviewRejectedBecause(rejectionReasonText(l, reason)),
                style: theme.textTheme.bodySmall,
              ),
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

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(text),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// Result of the reject dialog. Null (dialog dismissed) means "cancel".
class _RejectChoice {
  const _RejectChoice(this.reason);

  final RejectionReason? reason;
}

class _RejectDialog extends StatelessWidget {
  const _RejectDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SimpleDialog(
      title: Text(l.reviewRejectDialogTitle(count)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l.reviewRejectDialogHint),
        ),
        const SizedBox(height: 8),
        for (final reason in RejectionReason.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_RejectChoice(reason)),
            child: Text(rejectionReasonText(l, reason)),
          ),
        const Divider(),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(context).pop(const _RejectChoice(null)),
          child: Text(l.reviewRejectWithoutReason),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.reviewCancel),
        ),
      ],
    );
  }
}
