import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'teaching_actions.dart';
import 'teaching_strategy.dart';
import 'teaching_strategy_panel.dart';

/// Rebuilt with the existing live aggregate stream; no extra backend reads.
class TeachingActionsCard extends StatelessWidget {
  const TeachingActionsCard({
    super.key,
    required this.insights,
    required this.coveredConceptIds,
    required this.conceptNames,
    this.showStrategy = false,
    this.chooseStrategy,
    this.sessionId,
  });

  final ClassInsights insights;
  final Set<String> coveredConceptIds;
  final Map<String, String> conceptNames;
  final bool showStrategy;
  final TeachingStrategyChooser? chooseStrategy;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    final visible = insights.concepts.any((c) =>
        !c.suppressed &&
        c.respondents > 0 &&
        c.respondents >= insights.minGroupSize &&
        coveredConceptIds.contains(c.conceptId));
    if (!visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final actions = prioritizeTeachingActions(
      insights,
      coveredConceptIds: coveredConceptIds,
    );
    String name(String id) => conceptNames[id] ?? id;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 16),
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorActionsTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                )),
            const SizedBox(height: 6),
            Text(l.instructorActionsIntro,
                style: TextStyle(color: colors.onPrimaryContainer)),
            const SizedBox(height: 12),
            if (actions.isEmpty)
              Text(l.instructorActionsNone,
                  style: TextStyle(color: colors.onPrimaryContainer)),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const Divider(),
              _ActionRow(
                index: i + 1,
                action: actions[i],
                conceptName: name(actions[i].conceptId),
                relatedName: actions[i].relatedConceptId == null
                    ? null
                    : name(actions[i].relatedConceptId!),
              ),
            ],
            if (showStrategy && actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              TeachingStrategyPanel(
                key: ValueKey((sessionId, actions.first.conceptId,
                    actions.first.kind, actions.first.relatedConceptId,
                    actions.first.affectedCount, actions.first.groupCount,
                    name(actions.first.conceptId),
                    Localizations.localeOf(context).languageCode,
                    chooseStrategy != null)),
                action: actions.first,
                conceptName: name(actions.first.conceptId),
                relatedName: actions.first.relatedConceptId == null
                    ? null : name(actions.first.relatedConceptId!),
                choose: chooseStrategy,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.index,
    required this.action,
    required this.conceptName,
    required this.relatedName,
  });

  final int index;
  final TeachingAction action;
  final String conceptName;
  final String? relatedName;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (title, evidence, nextStep) = switch (action.kind) {
      TeachingActionKind.reviewPrerequisite => (
          l.instructorActionsReviewFoundation(conceptName),
          l.instructorActionsFoundationEvidence(
              action.affectedCount, action.groupCount, relatedName!),
          l.instructorActionsFoundationStep,
        ),
      TeachingActionKind.reviewConcept => (
          l.instructorActionsReviewConcept(conceptName),
          l.instructorActionsDifficultyEvidence(
              action.affectedCount, action.groupCount),
          l.instructorActionsReviewStep,
        ),
      TeachingActionKind.assessFurther => (
          l.instructorActionsAssess(conceptName),
          l.instructorActionsInsufficientEvidence(
              action.affectedCount, action.groupCount),
          l.instructorActionsAssessStep,
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          child: Text('$index'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 4),
              Text(evidence,
                  style: TextStyle(color: colors.onPrimaryContainer)),
              const SizedBox(height: 4),
              Text(nextStep,
                  style: TextStyle(color: colors.onPrimaryContainer)),
            ],
          ),
        ),
      ],
    );
  }
}
