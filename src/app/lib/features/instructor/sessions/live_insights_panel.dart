import 'dart:math' as math;

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import 'live_insights.dart';

typedef _InsightsContent = (
  List<Question>,
  List<AnswerKey>,
  List<Concept>,
);

class LiveInsightsPanel extends StatefulWidget {
  const LiveInsightsPanel({
    super.key,
    required this.session,
  });

  final Session session;

  @override
  State<LiveInsightsPanel> createState() =>
      _LiveInsightsPanelState();
}

class _LiveInsightsPanelState
    extends State<LiveInsightsPanel> {
  Future<_InsightsContent>? _content;
  Stream<List<Response>>? _responses;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final services = ServicesScope.of(context);

    _content ??= _loadContent(services);

    _responses ??= services.sessions.watchResponses(
      widget.session.id,
    );
  }

  Future<_InsightsContent> _loadContent(
    AppServices services,
  ) async {
    final courseId = widget.session.courseId;

    final questions =
        await services.content.questionsForSession(
      courseId,
      widget.session.questions,
    );

    final keys =
        await services.content.answerKeys(courseId);

    final concepts =
        await services.content.listConcepts(courseId);

    return (
      [for (final q in questions) q.question],
      keys,
      concepts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return FutureBuilder<_InsightsContent>(
      future: _content,
      builder: (context, contentSnapshot) {
        if (contentSnapshot.hasError) {
          return Text(l.errorGeneric);
        }

        if (!contentSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final (questions, keys, concepts) =
            contentSnapshot.data!;

        return StreamBuilder<List<Response>>(
          stream: _responses,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(l.errorGeneric);
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final insights = computeClassInsights(
              responses: snapshot.data!,
              questions: questions,
              keys: keys,
              concepts: concepts,
            );

            return _buildInsights(
              context,
              insights,
              concepts,
              // Only concepts this session asks about: the others have no
              // answers at all, and showing them as "hidden for privacy"
              // would give the wrong reason.
              {
                for (final q in questions) ...q.conceptIds,
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInsights(
    BuildContext context,
    ClassInsights insights,
    List<Concept> concepts,
    Set<String> covered,
  ) {
    final l = AppLocalizations.of(context);
    final language = currentLanguage(context);

    final names = {
      for (final concept in concepts)
        concept.id: concept.name.of(language),
    };

    final visibleIds = {
      for (final concept in insights.concepts)
        if (!concept.suppressed) concept.conceptId,
    };

    final signals = insights.prerequisiteSignals
        .where(
          (signal) =>
              visibleIds.contains(signal.conceptId) &&
              visibleIds.contains(signal.prerequisiteId),
        )
        .take(3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.instructorInsightsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),

        const SizedBox(height: 16),

        if (insights.participantCount == 0)
          Text(
            l.instructorInsightsWaiting(
              insights.minGroupSize,
            ),
          )
        else ...[
          for (final concept in insights.concepts)
            if (covered.contains(concept.conceptId))
            _ConceptInsightCard(
              name: names[concept.conceptId] ??
                  concept.conceptId,
              summary: concept,
              minGroupSize: insights.minGroupSize,
            ),

          if (signals.isNotEmpty) ...[
            const SizedBox(height: 24),

            Text(
              l.instructorInsightsPrerequisiteTitle,
              style:
                  Theme.of(context).textTheme.titleLarge,
            ),

            const SizedBox(height: 12),

            for (final signal in signals) ...[
              _InsightBullet(
                text: l.instructorInsightsStruggling(
                  signal.participantsStrugglingWithConcept,
                  names[signal.conceptId] ??
                      signal.conceptId,
                ),
              ),

              _InsightBullet(
                text: l.instructorInsightsGap(
                  signal.participantsWithPossibleGap,
                  names[signal.prerequisiteId] ??
                      signal.prerequisiteId,
                ),
              ),

              _InsightBullet(
                text: l.instructorInsightsPossibleCause(
                  names[signal.prerequisiteId] ??
                      signal.prerequisiteId,
                  names[signal.conceptId] ??
                      signal.conceptId,
                ),
              ),

              _InsightBullet(
                text:
                    l.instructorInsightsRecommendation(
                  names[signal.prerequisiteId] ??
                      signal.prerequisiteId,
                ),
              ),

              const SizedBox(height: 12),
            ],
          ],

          const SizedBox(height: 16),

          Text(
            l.instructorInsightsDisclaimer,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _InsightBullet extends StatelessWidget {
  const _InsightBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 7),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

const _stateColors = <Color>[
  Color(0xFFE16B71),
  Color(0xFFEAB64F),
  Color(0xFF32A685),
  Color(0xFF9CA3AF),
];

class _ConceptInsightCard extends StatelessWidget {
  const _ConceptInsightCard({
    required this.name,
    required this.summary,
    required this.minGroupSize,
  });

  final String name;
  final ConceptClassSummary summary;
  final int minGroupSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final states = [
      MasteryState.possibleDifficulty,
      MasteryState.emerging,
      MasteryState.demonstratedMastery,
      MasteryState.insufficientEvidence,
    ];

    final labels = [
      l.instructorInsightsStateDifficulty,
      l.instructorInsightsStateEmerging,
      l.instructorInsightsStateMastery,
      l.instructorInsightsStateInsufficient,
    ];

    final counts = [
      for (final state in states)
        summary.stateCounts[state] ?? 0,
    ];

    return Card(
      margin: const EdgeInsetsDirectional.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 8),

            if (summary.suppressed)
              Row(
                children: [
                  const Icon(Icons.lock_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.instructorInsightsHidden(
                        minGroupSize,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              Text(
                l.instructorInsightsEvidence(
                  summary.respondents,
                  (summary.pooledAccuracy! * 100).round(),
                ),
              ),

              const SizedBox(height: 16),

              LayoutBuilder(
                builder: (context, constraints) {
                  final chart = SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(140, 140),
                          painter: _DonutPainter(counts),
                        ),

                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${summary.respondents}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium,
                            ),
                            Text(
                              l.instructorInsightsStudents,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );

                  final legend = Column(
                    children: [
                      for (var i = 0; i < states.length; i++)
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.only(
                            bottom: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 12,
                                color: _stateColors[i],
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: Text(labels[i]),
                              ),

                              Text(
                                '${counts[i]}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(width: 8),

                              Text(
                                '${(counts[i] * 100 / summary.respondents).round()}%',
                              ),
                            ],
                          ),
                        ),
                    ],
                  );

                  if (constraints.maxWidth < 400) {
                    return Column(
                      children: [
                        chart,
                        const SizedBox(height: 16),
                        legend,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      chart,
                      const SizedBox(width: 24),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.counts);

  final List<int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    if (total == 0) return;

    const strokeWidth = 22.0;

    final radius =
        (math.min(size.width, size.height) -
                strokeWidth) /
            2;

    final rect = Rect.fromCircle(
      center: Offset(
        size.width / 2,
        size.height / 2,
      ),
      radius: radius,
    );

    var startAngle = -math.pi / 2;

    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;

      final sweepAngle =
          2 * math.pi * counts[i] / total;

      final paint = Paint()
        ..color = _stateColors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(
    covariant _DonutPainter oldDelegate,
  ) {
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] != oldDelegate.counts[i]) {
        return true;
      }
    }

    return false;
  }
}