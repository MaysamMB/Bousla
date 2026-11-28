import 'dart:async';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback.dart';
import '../../../data/resource_review.dart' show isWebLink;
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/open_link.dart' as shared;
import '../../../shared/widgets/language_switcher.dart';
import '../profile/save_progress_card.dart';
import '../knowledge_map/knowledge_map_screen.dart';
import '../../../data/repositories/follow_up_repository.dart';
import 'follow_up_screen.dart';
import 'practice_attempt.dart';
import 'review_marks_store.dart';

/// A student's personal feedback for one session (owner: student web
/// portal). Shows, in this order: concept states with their evidence,
/// possible prerequisites (worded as possibilities), next steps with
/// approved resources, and the explanation (labelled when AI wrote it).
///
/// Everything comes from the student's own feedback document, written by
/// the instructor app from the engine's results; nothing is computed here.
/// Opens in the language the student answered in; the language switcher
/// still works.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.sessionId,
    required this.participantId,
    this.reviewStore,
  });

  final String sessionId;
  final String participantId;

  /// Where the "I've reviewed this concept" ticks are kept: this browser's
  /// localStorage unless a test passes another.
  final ReviewMarksStore? reviewStore;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  Stream<StudentFeedback?>? _feedback;
  var _languageApplied = false;
  StudentFeedback? _last;
  late final ReviewMarksStore _reviewStore =
      widget.reviewStore ?? ReviewMarksStore.browser();

  /// The student's own ticks for this session (local only, see
  /// [ReviewMarksStore]).
  late Set<String> _reviewed =
      _reviewStore.load(widget.sessionId, widget.participantId);

  void _setReviewed(String conceptId, bool reviewed) {
    setState(() {
      _reviewed = {..._reviewed};
      reviewed ? _reviewed.add(conceptId) : _reviewed.remove(conceptId);
    });
    _reviewStore.save(widget.sessionId, widget.participantId, _reviewed);
  }

  /// This student's private follow-up for the session, if one was started
  /// (to show "continue" or "see results").
  FollowUpStatus? _followUpStatus;
  var _attemptChecked = false;

  Future<void> _checkAttempt() async {
    // Not during the build that called this.
    await Future<void>.value();
    if (!mounted) return;
    final practice = PracticeAttempt.tryParse(
        _reviewStore.readPractice(widget.sessionId, widget.participantId));
    if (practice != null) {
      setState(() => _followUpStatus = practice.finished
          ? FollowUpStatus.finished
          : FollowUpStatus.inProgress);
      return;
    }
    final followUps = ServicesScope.of(context).followUps;
    if (followUps == null) return;
    try {
      final a = await followUps.findAttempt(widget.sessionId);
      if (mounted) setState(() => _followUpStatus = a?.status);
    } catch (_) {
      // Not known: the button starts or resumes it anyway.
    }
  }

  Future<void> _openFollowUp(StudentFeedback feedback) async {
    final reviewed = [
      for (final id in feedback.reviewConceptIds)
        if (_reviewed.contains(id)) id,
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowUpScreen(
          sessionId: widget.sessionId,
          participantId: widget.participantId,
          feedback: feedback,
          reviewedConceptIds: reviewed,
          store: _reviewStore,
        ),
      ),
    );
    if (mounted) await _checkAttempt();
  }

  Widget _view(StudentFeedback feedback) {
    final services = ServicesScope.of(context);
    final canFollowUp = services.followUps != null ||
        services.practiceQuizGenerator != null;
    return FeedbackView(
      feedback: feedback,
      reviewed: _reviewed,
      onReviewChanged: _setReviewed,
      followUpStatus: _followUpStatus,
      onTestAgain: canFollowUp ? () => _openFollowUp(feedback) : null,
      // Optional: keep this session in the student's own profile.
      footer: SaveProgressCard(
        sessionId: widget.sessionId,
        feedback: feedback,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedback ??= ServicesScope.of(context)
        .sessions
        .watchMyFeedback(widget.sessionId, widget.participantId);
    if (!_attemptChecked) {
      _attemptChecked = true;
      _checkAttempt();
    }
  }

  /// Switches the UI to the feedback's language once, when it first arrives.
  void _applyLanguage(StudentFeedback feedback) {
    if (_languageApplied) return;
    _languageApplied = true;
    final services = ServicesScope.of(context);
    final code = feedback.language.name;
    if (services.locale.value.languageCode != code) {
      scheduleMicrotask(() => services.locale.value = Locale(code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentFeedbackTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: StreamBuilder<StudentFeedback?>(
        stream: _feedback,
        builder: (context, snapshot) {
          // After the student signs in to their existing profile, this
          // browser's anonymous feedback can no longer be read: keep showing
          // what was already shown.
          if (snapshot.hasError && _last != null) {
            return _view(_last!);
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(l.errorGeneric, textAlign: TextAlign.center),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final feedback = snapshot.data;
          if (feedback == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.studentFeedbackNotAvailable,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _last = feedback;
          _applyLanguage(feedback);
          return _view(feedback);
        },
      ),
    );
  }
}

/// The feedback itself, in the current UI language.
class FeedbackView extends StatelessWidget {
  const FeedbackView({
    super.key,
    required this.feedback,
    this.openLink = shared.openLink,
    this.footer,
    this.reviewed = const {},
    this.onReviewChanged,
    this.onTestAgain,
    this.followUpStatus,
  });

  /// Opens the private follow-up test. Null: no button.
  final VoidCallback? onTestAgain;

  /// The follow-up already started, if any: the button then continues it
  /// or shows its results (and does not need a tick).
  final FollowUpStatus? followUpStatus;

  final StudentFeedback feedback;

  /// Concepts the student ticked as reviewed (their own note; see
  /// [ReviewMarksStore]).
  final Set<String> reviewed;

  /// Called when a tick changes. Null: no ticks and no follow-up button
  /// (e.g. where the feedback is only shown).
  final void Function(String conceptId, bool reviewed)? onReviewChanged;

  /// Shown last (the "keep your progress" card on the feedback screen).
  final Widget? footer;

  /// Opens a resource's link (the shared [shared.openLink]; replaced in
  /// tests).
  final void Function(String url) openLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = currentLanguage(context);
    final theme = Theme.of(context);
    final names = {
      for (final c in feedback.concepts) c.conceptId: c.name.of(language),
    };
    String name(String? id) => names[id] ?? id ?? '';
    final explanation = feedback.explanation;

    // "I've reviewed this concept": only for concepts the feedback says may
    // need review or are still forming. The tick is placed under the
    // concept's first next step (its resources); a concept with no step
    // gets it on its own card. It changes nothing in the feedback.
    final onReview = onReviewChanged;
    final eligible = onReview == null
        ? const <String>{}
        : {
            for (final c in feedback.concepts)
              if (needsReviewTick(c.state)) c.conceptId,
          };
    final tickInStep = <int, String>{};
    for (var i = 0; i < feedback.recommendations.length; i++) {
      final id = feedback.recommendations[i].conceptId;
      if (eligible.contains(id) && !tickInStep.containsValue(id)) {
        tickInStep[i] = id;
      }
    }
    final anyReviewed = reviewed.any(eligible.contains);
    Widget tick(String conceptId) => _ReviewedTick(
          conceptId: conceptId,
          value: reviewed.contains(conceptId),
          onChanged: (v) => onReview!(conceptId, v),
        );

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(text, style: theme.textTheme.titleMedium),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.studentFeedbackIntro, style: theme.textTheme.bodyMedium),

            // A. Concepts, each with its evidence.
            heading(l.studentFeedbackConceptsTitle),
            for (final c in feedback.concepts)
              Card(
                key: ValueKey('concept-${c.conceptId}'),
                child: ListTile(
                  leading: Icon(_stateIcon(c.state)),
                  title: Text(c.name.of(language)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stateLabel(l, c.state),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        c.attempts == 0
                            ? l.studentFeedbackNoEvidence
                            : l.studentFeedbackEvidence(c.correct, c.attempts),
                      ),
                      if (eligible.contains(c.conceptId) &&
                          !tickInStep.containsValue(c.conceptId))
                        tick(c.conceptId),
                    ],
                  ),
                ),
              ),

            // B. Possible prerequisites: possibilities, never a diagnosis.
            if (feedback.hints.isNotEmpty) ...[
              heading(l.studentFeedbackHintsTitle),
              for (final h in feedback.hints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    h.signal == PrerequisiteSignal.possibleContributingGap
                        ? l.studentFeedbackHintGap(
                            name(h.prerequisiteId),
                            name(h.conceptId),
                          )
                        : l.studentFeedbackHintMoreEvidence(
                            name(h.prerequisiteId),
                            name(h.conceptId),
                          ),
                  ),
                ),
              Text(l.studentFeedbackHintsNote, style: theme.textTheme.bodySmall),
            ],

            // C. Next steps with approved resources only.
            heading(l.studentFeedbackNextStepsTitle),
            if (feedback.recommendations.isEmpty)
              Text(l.studentFeedbackNoSteps)
            else
              for (final (i, r) in feedback.recommendations.indexed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _stepText(l, r, name),
                          style: theme.textTheme.bodyLarge,
                        ),
                        for (final res in r.resources)
                          _ResourceTile(
                            resource: res,
                            language: language,
                            openLink: openLink,
                          ),
                        if (tickInStep[i] case final id?) tick(id),
                      ],
                    ),
                  ),
                ),

            // C2. Test my understanding again: the student's own private
            // follow-up (no instructor, no class session). The ticks only
            // choose its concepts; its graded answers are the evidence.
            if (eligible.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.studentFeedbackReviewedNote,
                  style: theme.textTheme.bodySmall),
              if (onTestAgain case final open?) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const ValueKey('follow-up-start'),
                    onPressed: anyReviewed || followUpStatus != null
                        ? open
                        : null,
                    icon: Icon(followUpStatus == FollowUpStatus.finished
                        ? Icons.insights
                        : Icons.quiz_outlined),
                    label: Text(switch (followUpStatus) {
                      null => l.studentFeedbackTestAgain,
                      FollowUpStatus.inProgress =>
                        l.studentFeedbackTestAgainContinue,
                      FollowUpStatus.finished =>
                        l.studentFeedbackTestAgainResults,
                    }),
                  ),
                ),
              ],
            ],

            // D. The explanation, right after the evidence it is based on.
            if (explanation != null) ...[
              heading(l.studentFeedbackExplanationTitle),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (explanation.source == ExplanationSource.ai) ...[
                        Chip(
                          key: const ValueKey('ai-label'),
                          avatar: const Icon(Icons.auto_awesome, size: 18),
                          label: Text(l.studentFeedbackAiLabel),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        explanation.text.of(language),
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (explanation.source == ExplanationSource.ai) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.studentFeedbackAiNote,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // E. More detail on another page: the same results as a map
            // from foundations up, which the student can save as an image.
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(l.studentMapOpen),
                subtitle: Text(l.studentMapOpenHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => KnowledgeMapScreen(feedback: feedback),
                  ),
                ),
              ),
            ),
            if (footer case final f?) ...[
              const SizedBox(height: 16),
              f,
            ],
          ],
        ),
      ),
    );
  }
}

/// The states whose concepts get an "I've reviewed this concept" tick:
/// "may need review" and "still forming".
bool needsReviewTick(MasteryState state) =>
    state == MasteryState.possibleDifficulty || state == MasteryState.emerging;

/// One "I've reviewed this concept" tick.
class _ReviewedTick extends StatelessWidget {
  const _ReviewedTick({
    required this.conceptId,
    required this.value,
    required this.onChanged,
  });

  final String conceptId;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CheckboxListTile(
      key: ValueKey('reviewed-$conceptId'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(l.studentFeedbackReviewedConcept),
    );
  }
}

/// The wording for each engine state (docs: never a diagnosis).
String stateLabel(AppLocalizations l, MasteryState state) => switch (state) {
      MasteryState.insufficientEvidence => l.studentStateInsufficientEvidence,
      MasteryState.possibleDifficulty => l.studentStatePossibleDifficulty,
      MasteryState.emerging => l.studentStateEmerging,
      MasteryState.demonstratedMastery => l.studentStateDemonstratedMastery,
    };

IconData _stateIcon(MasteryState state) => switch (state) {
      MasteryState.insufficientEvidence => Icons.help_outline,
      MasteryState.possibleDifficulty => Icons.replay,
      MasteryState.emerging => Icons.trending_up,
      MasteryState.demonstratedMastery => Icons.check_circle_outline,
    };

String _stepText(
  AppLocalizations l,
  FeedbackRecommendation r,
  String Function(String?) name,
) =>
    switch (r.reason) {
      RecommendationReason.reviewPrerequisite =>
        l.studentFeedbackStepReviewPrerequisite(
          name(r.conceptId),
          name(r.relatedConceptId),
        ),
      RecommendationReason.reviewConcept =>
        l.studentFeedbackStepReviewConcept(name(r.conceptId)),
      RecommendationReason.practice =>
        l.studentFeedbackStepPractice(name(r.conceptId)),
      RecommendationReason.assessMore =>
        l.studentFeedbackStepAssessMore(name(r.conceptId)),
    };

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.resource,
    required this.language,
    required this.openLink,
  });

  final FeedbackResource resource;
  final Language language;
  final void Function(String url) openLink;

  /// In the student's language, else the other one; null when there is none.
  String? get _description {
    final d = resource.description;
    if (d == null) return null;
    for (final t in [d.of(language), d.ar, d.en]) {
      if (t.trim().isNotEmpty) return t.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final raw = resource.url?.trim() ?? '';
    // Only the URL stored with the approved resource, and only a web link
    // (http/https with a host): anything else is never opened.
    final url = raw.isNotEmpty && isWebLink(raw) ? raw : null;
    final description = _description;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (resource.type) {
        ResourceType.video => Icons.play_circle_outline,
        ResourceType.link => Icons.link,
        ResourceType.file => Icons.description_outlined,
        ResourceType.activity => Icons.edit_note,
      }),
      title: Text(resource.title.of(language)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(description, style: theme.textTheme.bodyMedium),
            ),
          if (url != null)
            // Links are read left-to-right in both languages.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                url,
                semanticsLabel: l.studentFeedbackResourceLink(url),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else if (description == null)
            Text(l.studentFeedbackResourceActivity),
        ],
      ),
      trailing: url == null ? null : const Icon(Icons.open_in_new),
      onTap: url == null ? null : () => openLink(url),
    );
  }
}
