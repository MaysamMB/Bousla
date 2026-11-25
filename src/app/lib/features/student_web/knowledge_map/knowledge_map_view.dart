import 'dart:ui' as ui;

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../data/feedback.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import 'knowledge_map_layout.dart';
import 'save_image.dart' as device;

/// Saves PNG bytes on the device; replaced in tests.
typedef SaveImage = Future<void> Function(Uint8List png, String fileName);

/// The student's knowledge map for ONE session: the session's concepts from
/// foundations to the ones built on them, each with its estimated state and
/// the evidence behind it, and which earlier concept it builds on.
///
/// It is drawn from the released feedback only, so it says nothing beyond
/// this session (no longitudinal claim). States are estimates, labelled as
/// such. "Save" turns the map into an image on the student's phone; nothing
/// is uploaded.
///
/// Place it in the feedback screen: `KnowledgeMapView(feedback: feedback)`.
class KnowledgeMapView extends StatefulWidget {
  const KnowledgeMapView({
    super.key,
    required this.feedback,
    this.saveImage = device.saveImage,
    this.fileName = 'bousla-knowledge-map.png',
  });

  final StudentFeedback feedback;
  final SaveImage saveImage;
  final String fileName;

  @override
  State<KnowledgeMapView> createState() => _KnowledgeMapViewState();
}

class _KnowledgeMapViewState extends State<KnowledgeMapView> {
  final _mapKey = GlobalKey();
  var _saving = false;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      final boundary =
          _mapKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await widget.saveImage(data!.buffer.asUint8List(), widget.fileName);
      messenger?.showSnackBar(SnackBar(content: Text(l.studentMapSaved)));
    } catch (e) {
      debugPrint('Bousla map save: $e');
      messenger?.showSnackBar(SnackBar(content: Text(l.studentMapSaveFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Everything inside the boundary is what the saved image shows,
        // on an opaque background (a PNG is transparent otherwise).
        RepaintBoundary(
          key: _mapKey,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _MapContent(feedback: widget.feedback),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(l.studentMapSave),
        ),
      ],
    );
  }
}

class _MapContent extends StatelessWidget {
  const _MapContent({required this.feedback});

  final StudentFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = currentLanguage(context);
    final names = {
      for (final c in feedback.concepts) c.conceptId: c.name.of(language),
    };
    // Prerequisites that may be contributing, per concept (engine output).
    final gaps = <String, List<String>>{};
    for (final h in feedback.hints) {
      if (h.signal == PrerequisiteSignal.possibleContributingGap &&
          names.containsKey(h.prerequisiteId)) {
        (gaps[h.conceptId] ??= []).add(h.prerequisiteId);
      }
    }
    final levels = knowledgeMapLevels(feedback.concepts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.studentMapTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(l.studentMapNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (levels.isEmpty) Text(l.studentMapEmpty),
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0)
            // Reads "these build on the level above".
            const Icon(Icons.arrow_downward, size: 20),
          Text(
            i == 0 ? l.studentMapFoundations : l.studentMapLevel(i + 1),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          for (final c in levels[i])
            _ConceptCard(
              concept: c,
              name: names[c.conceptId]!,
              buildsOn: [
                for (final p in c.prerequisites)
                  if (names[p] case final n?) n,
              ],
              possibleGaps: [for (final g in gaps[c.conceptId] ?? []) names[g]!],
            ),
        ],
        const SizedBox(height: 12),
        _Legend(),
      ],
    );
  }
}

/// How each state looks. Never only a colour: there is always an icon and
/// a word, and "not enough evidence" is neutral, not alarming.
({IconData icon, Color color, String label}) _styleOf(
  BuildContext context,
  MasteryState state,
) {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  // Lighter shades on the dark theme, so they stay readable.
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (state) {
    MasteryState.possibleDifficulty => (
        icon: Icons.flag_outlined,
        color: dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
        label: l.studentStatePossibleDifficulty,
      ),
    MasteryState.emerging => (
        icon: Icons.trending_up,
        color: scheme.primary,
        label: l.studentStateEmerging,
      ),
    MasteryState.demonstratedMastery => (
        icon: Icons.check_circle_outline,
        color: dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
        label: l.studentStateDemonstratedMastery,
      ),
    MasteryState.insufficientEvidence => (
        icon: Icons.help_outline,
        color: scheme.outline,
        label: l.studentStateInsufficientEvidence,
      ),
  };
}

class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.concept,
    required this.name,
    required this.buildsOn,
    required this.possibleGaps,
  });

  final FeedbackConcept concept;
  final String name;
  final List<String> buildsOn;
  final List<String> possibleGaps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = _styleOf(context, concept.state);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: style.color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              concept.attempts == 0
                  ? style.label
                  : '${style.label} · '
                      '${l.studentFeedbackEvidence(concept.correct, concept.attempts)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: style.color),
            ),
            if (buildsOn.isNotEmpty)
              Text(
                l.studentMapBuildsOn(
                  buildsOn.join(
                    currentLanguage(context) == Language.ar ? '، ' : ', ',
                  ),
                ),
                style: theme.textTheme.bodySmall,
              ),
            for (final g in possibleGaps)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4),
                child: Text(
                  l.studentMapPossibleGap(g),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final s in const [
            MasteryState.possibleDifficulty,
            MasteryState.emerging,
            MasteryState.demonstratedMastery,
            MasteryState.insufficientEvidence,
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_styleOf(context, s).icon,
                    size: 16, color: _styleOf(context, s).color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _styleOf(context, s).label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      );
}
