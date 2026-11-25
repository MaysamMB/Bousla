import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'concept_overview.dart';

const _colors = [
  Color(0xFFE16B71),
  Color(0xFFEAB64F),
  Color(0xFF32A685),
  Color(0xFF9CA3AF),
];

/// Compact overview above the detailed per-concept charts.
/// Reuses live aggregates; makes no additional Firebase or Gemini calls.
class ConceptOverviewCard extends StatelessWidget {
  const ConceptOverviewCard({
    super.key,
    required this.insights,
    required this.coveredConceptIds,
    required this.conceptNames,
    this.presentationMode = false,
  });

  final ClassInsights insights;
  final Set<String> coveredConceptIds;
  final Map<String, String> conceptNames;
  final bool presentationMode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final overview = buildConceptOverview(insights, coveredConceptIds);
    if (overview.coveredCount == 0) return const SizedBox.shrink();
    final labels = [
      l.instructorInsightsStateDifficulty,
      l.instructorInsightsStateEmerging,
      l.instructorInsightsStateMastery,
      l.instructorInsightsStateInsufficient,
    ];
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorOverviewTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(l.instructorOverviewIntro),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 4 :
                  constraints.maxWidth >= 220 ? 2 : 1;
              final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
              final metrics = [
                (overview.coveredCount, l.instructorOverviewCovered),
                (overview.visible.length, l.instructorOverviewVisible),
                (overview.reviewCount, l.instructorOverviewReview),
                (overview.assessCount, l.instructorOverviewAssess),
              ];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in metrics)
                    SizedBox(width: width, child: _Metric(value, label)),
                ],
              );
            }),
            if (overview.hiddenCount > 0) ...[
              const SizedBox(height: 12),
              Text(l.instructorOverviewHidden(overview.hiddenCount)),
            ],
            const SizedBox(height: 16),
            if (overview.visible.isEmpty)
              Text(l.instructorOverviewNoVisible)
            else ...[
              Text(l.instructorOverviewComparison,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final concept in overview.visible) ...[
                _ConceptRow(
                  summary: concept,
                  name: conceptNames[concept.conceptId] ?? concept.conceptId,
                  labels: labels,
                  presentationMode: presentationMode,
                ),
                const SizedBox(height: 12),
              ],
            ],
            Text(l.instructorOverviewNote, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({required this.summary, required this.name,
      required this.labels, required this.presentationMode});

  final ConceptClassSummary summary;
  final String name;
  final List<String> labels;
  final bool presentationMode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final counts = [for (final state in overviewStates)
      summary.stateCounts[state] ?? 0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: theme.textTheme.titleSmall),
        Text(l.instructorOverviewRespondents(summary.respondents)),
        const SizedBox(height: 6),
        // Exact counts in the legend keep meaning available without color.
        // In RTL the bar and legend both follow the reading direction.
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: presentationMode ? 28 : 18,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < counts.length; i++)
                  if (counts[i] > 0)
                    Expanded(flex: counts[i],
                        child: ColoredBox(color: _colors[i])),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < counts.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: _colors[i]),
                  const SizedBox(width: 4),
                  Flexible(child: Text('${labels[i]}: ${counts[i]} '
                      '(${(100 * counts[i] / summary.respondents).round()}%)',
                      style: presentationMode
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
