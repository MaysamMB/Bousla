import 'dart:async';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../answering/answering_screen.dart';
import '../knowledge_map/knowledge_map_view.dart';

/// A student's released feedback for one session (owner: student portal;
/// the content is Lina's task, docs/implementation-plan.md Phase 5).
///
/// Reached from the thank-you screen when feedback is released, and from the
/// join screen when the session is closed and feedback is released (a
/// student coming back to the link later, from the same browser: same
/// anonymous account).
///
/// Shows, above the knowledge map: the personal explanation (with an
/// "AI-generated" label only when `source == ai`), then the next steps with
/// approved resources. Everything is read from the student's own saved
/// document; nothing is computed here and no model is called, so reopening
/// or refreshing shows the same feedback. Opens in the feedback's language;
/// the language switcher still works.
class MyFeedbackScreen extends StatefulWidget {
  const MyFeedbackScreen({
    super.key,
    required this.session,
    required this.participantId,
  });

  final Session session;
  final String participantId;

  @override
  State<MyFeedbackScreen> createState() => _MyFeedbackScreenState();
}

class _MyFeedbackScreenState extends State<MyFeedbackScreen> {
  Stream<StudentFeedback?>? _feedback;
  var _languageApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One stream for the screen's life, so rebuilds do not re-subscribe.
    _feedback ??= ServicesScope.of(context)
        .sessions
        .watchMyFeedback(widget.session.id, widget.participantId)
        .timeout(AnsweringScreen.timeout);
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
            return _Message(
              snapshot.error is TimeoutException
                  ? l.studentConnectionSlow
                  : l.errorGeneric,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final feedback = snapshot.data;
          // Released, but nothing for this account: did not answer in this
          // session, or answered from another phone or browser.
          if (feedback == null) return _Message(l.studentFeedbackNone);
          _applyLanguage(feedback);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FeedbackSummary(feedback: feedback),
                  const SizedBox(height: 16),
                  KnowledgeMapView(feedback: feedback),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

/// The explanation and the next steps, shown above the knowledge map.
class FeedbackSummary extends StatelessWidget {
  const FeedbackSummary({super.key, required this.feedback});

  final StudentFeedback feedback;

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
    final isAi = explanation?.source == ExplanationSource.ai;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(text, style: theme.textTheme.titleMedium),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1-2. The explanation, labelled when AI wrote it.
        if (explanation != null) ...[
          heading(l.studentFeedbackExplanationTitle),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isAi) ...[
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
                  if (isAi) ...[
                    const SizedBox(height: 8),
                    Text(l.studentFeedbackAiNote,
                        style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
        // 3-5. Next steps with approved resources only.
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
                    Text(_stepText(l, r, name),
                        style: theme.textTheme.bodyLarge),
                    for (final res in r.resources)
                      _ResourceTile(resource: res, language: language),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

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
  const _ResourceTile({required this.resource, required this.language});

  final FeedbackResource resource;
  final Language language;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final url = resource.url;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (resource.type) {
        ResourceType.video => Icons.play_circle_outline,
        ResourceType.link => Icons.link,
        ResourceType.file => Icons.description_outlined,
        ResourceType.activity => Icons.edit_note,
      }),
      title: Text(resource.title.of(language)),
      // Only the URL stored with the approved resource; links read
      // left-to-right in both languages.
      subtitle: url == null || url.isEmpty
          ? Text(l.studentFeedbackResourceActivity)
          : Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                url,
                semanticsLabel: l.studentFeedbackResourceLink(url),
              ),
            ),
    );
  }
}
