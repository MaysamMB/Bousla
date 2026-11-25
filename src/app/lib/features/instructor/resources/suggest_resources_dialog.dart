import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/ai/question_generator.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../content_review/generate_from_material.dart';

/// Asks AI to describe resources for the chosen concepts (one request). The
/// descriptions are saved as pending, without links, and the dialog pops a
/// one-line summary for the screen. The material file is optional.
class SuggestResourcesDialog extends StatefulWidget {
  const SuggestResourcesDialog({
    super.key,
    required this.courseId,
    required this.concepts,
    this.pickMaterial,
  });

  final String courseId;

  /// Approved concepts.
  final List<Concept> concepts;
  final PickMaterial? pickMaterial;

  @override
  State<SuggestResourcesDialog> createState() => _SuggestResourcesDialogState();
}

class _SuggestResourcesDialogState extends State<SuggestResourcesDialog> {
  late final Set<String> _chosen = {for (final c in widget.concepts) c.id};
  var _perConcept = 2;
  MaterialFile? _file;
  var _busy = false;
  GenerationProblem? _problem;
  var _nothingUsable = false;

  Future<void> _pick() async {
    setState(() => _problem = null);
    try {
      final file = await (widget.pickMaterial ?? pickMaterialFile)();
      if (file != null && mounted) setState(() => _file = file);
    } on QuestionGenerationException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    }
  }

  Future<void> _run() async {
    final l = AppLocalizations.of(context);
    final services = ServicesScope.of(context);
    final suggester = services.resourceSuggester!;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _problem = null;
      _nothingUsable = false;
    });
    try {
      final result = await suggester.suggestResources(
        concepts: [
          for (final c in widget.concepts)
            if (_chosen.contains(c.id)) c,
        ],
        perConcept: _perConcept,
        material: _file,
      );
      if (result.accepted.isEmpty) {
        if (mounted) setState(() => _nothingUsable = true);
        return;
      }
      await services.content.saveAiResourceSuggestions(
        widget.courseId,
        modelName: suggester.modelName,
        suggestions: result.accepted,
      );
      final links = result.dropped
          .where((i) => i == SuggestionIssue.containsLink)
          .length;
      navigator.pop(
        l.instructorResSuggestDone(
          result.accepted.length,
          result.dropped.length,
          links,
        ),
      );
    } on QuestionGenerationException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    } catch (_) {
      if (mounted) setState(() => _problem = GenerationProblem.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    final theme = Theme.of(context);
    final file = _file;
    return AlertDialog(
      title: Text(l.instructorResSuggest),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.instructorResSuggestHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(l.instructorResFieldConcepts),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in widget.concepts)
                    FilterChip(
                      label: Text(c.name.of(lang)),
                      selected: _chosen.contains(c.id),
                      onSelected: _busy
                          ? null
                          : (on) => setState(
                                () =>
                                    on ? _chosen.add(c.id) : _chosen.remove(c.id),
                              ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(l.instructorResPerConcept),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  for (final n in const [1, 2, 3])
                    ButtonSegment(value: n, label: Text('$n')),
                ],
                selected: {_perConcept},
                onSelectionChanged:
                    _busy ? null : (v) => setState(() => _perConcept = v.first),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: Text(l.instructorResPickOptional),
              ),
              if (file != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    file.name,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_problem case final p?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    generationProblemText(l, p),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_nothingUsable)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l.instructorResSuggestNothing,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.reviewCancel),
        ),
        FilledButton(
          onPressed: _busy || _chosen.isEmpty ? null : _run,
          child: Text(l.instructorResSuggestStart),
        ),
      ],
    );
  }
}
