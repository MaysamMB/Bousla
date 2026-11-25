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
import '../knowledge_map/knowledge_map_screen.dart';

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
  });

  final String sessionId;
  final String participantId;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  Stream<StudentFeedback?>? _feedback;
  var _languageApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedback ??= ServicesScope.of(context)
        .sessions
        .watchMyFeedback(widget.sessionId, widget.participantId);
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
          _applyLanguage(feedback);
          return FeedbackView(feedback: feedback);
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
  });

  final StudentFeedback feedback;

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
              for (final r in feedback.recommendations)
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
                      ],
                    ),
                  ),
                ),

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
          ],
        ),
      ),
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
