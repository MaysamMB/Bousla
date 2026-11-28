import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/ai/question_generator.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../content_review/generate_from_material.dart';
import '../sessions/past_sessions_screen.dart' show sessionTitleText;
import 'session_focus.dart';

/// Asks AI to describe resources for the chosen concepts (one request). The
/// descriptions are saved as pending, without links, and the dialog pops a
/// one-line summary for the screen. The material file is optional.
///
/// The instructor may describe what they need in their own words. Without a
/// description, the latest session's class results (aggregate only) guide
/// the suggestions, and the concepts they point to are chosen first.
/// Suggestions whose title a course resource already has are not saved.
class SuggestResourcesDialog extends StatefulWidget {
  const SuggestResourcesDialog({
    super.key,
    required this.courseId,
    required this.concepts,
    this.pickMaterial,
    this.loadFocus,
  });

  final String courseId;

  /// Replaced in tests; by default [loadLatestSessionFocus].
  final Future<SessionFocus?> Function()? loadFocus;

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
  var _allDuplicates = false;
  final _request = TextEditingController();
  SessionFocus? _focus;
  var _focusLoaded = false;
  var _focusRequested = false;

  /// The instructor changed the concept choice: the session focus no longer
  /// changes it.
  var _chosenTouched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusRequested) return;
    _focusRequested = true;
    final services = ServicesScope.of(context);
    final load = widget.loadFocus ??
        () => loadLatestSessionFocus(services, widget.courseId);
    load().then((f) {
      if (!mounted) return;
      setState(() {
        _focus = f;
        _focusLoaded = true;
        final known = {for (final c in widget.concepts) c.id};
        final ids = [
          for (final id in f?.focus.conceptIds ?? const <String>[])
            if (known.contains(id)) id,
        ];
        if (ids.isNotEmpty && !_chosenTouched) {
          _chosen
            ..clear()
            ..addAll(ids);
        }
      });
    });
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

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
      _allDuplicates = false;
    });
    final request = _request.text.trim();
    try {
      // Search context from the approved questions on these concepts
      // (prompts only), so the instructor need not describe anything.
      final questionsByConcept = <String, List<String>>{};
      try {
        final questions = await services.content
            .listQuestions(widget.courseId, approvedOnly: true);
        for (final q in questions) {
          final text = q.prompt.en.trim().isNotEmpty
              ? q.prompt.en.trim()
              : q.prompt.ar.trim();
          if (text.isEmpty) continue;
          for (final id in q.question.conceptIds) {
            if (_chosen.contains(id)) {
              (questionsByConcept[id] ??= []).add(text);
            }
          }
        }
      } catch (e) {
        // Without questions the concept names alone guide the search.
        debugPrint('Questions for the resource search: $e');
      }
      final result = await suggester.suggestResources(
        questionsByConcept: questionsByConcept,
        concepts: [
          for (final c in widget.concepts)
            if (_chosen.contains(c.id)) c,
        ],
        perConcept: _perConcept,
        material: _file,
        request: request.isEmpty ? null : request,
        focus: request.isEmpty ? _focus?.focus : null,
      );
      if (result.accepted.isEmpty) {
        if (mounted) setState(() => _nothingUsable = true);
        return;
      }
      // Not the same resource twice: titles the course already has are
      // skipped (rejected ones excepted).
      final (fresh, duplicates) = withoutExistingResources(
        result.accepted,
        await services.content.listResources(
          widget.courseId,
          approvedOnly: false,
        ),
      );
      if (fresh.isEmpty) {
        if (mounted) setState(() => _allDuplicates = true);
        return;
      }
      await services.content.saveAiResourceSuggestions(
        widget.courseId,
        modelName: suggester.modelName,
        suggestions: fresh,
      );
      final links = result.dropped
          .where((i) =>
              i == SuggestionIssue.containsLink ||
              i == SuggestionIssue.ungroundedLink)
          .length;
      final done = l.instructorResSuggestDone(
        fresh.length,
        result.dropped.length,
        links,
      );
      navigator.pop(
        duplicates == 0
            ? done
            : '$done ${l.instructorResSuggestDuplicates(duplicates)}',
      );
    } on QuestionGenerationException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    } catch (_) {
      if (mounted) setState(() => _problem = GenerationProblem.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _focusText(AppLocalizations l, Language lang) {
    final f = _focus;
    if (f == null || f.focus.isEmpty) return l.instructorResFocusNone;
    final names = {for (final c in widget.concepts) c.id: c.name.of(lang)};
    final listed = [
      for (final id in f.focus.conceptIds)
        if (names[id] != null) names[id]!,
    ];
    return l.instructorResFocusFrom(
      sessionTitleText(context, f.session),
      listed.join(lang == Language.ar ? '، ' : ', '),
    );
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
              Text(l.instructorResSuggestHelp,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: _request,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                maxLength: maxResourceRequestLength,
                decoration: InputDecoration(
                  labelText: l.instructorResRequestLabel,
                  helperText: l.instructorResRequestHint,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              // What guides the suggestions when nothing is written.
              if (_request.text.trim().isEmpty && _focusLoaded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _focusText(l, lang),
                    key: const ValueKey('resource-focus'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
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
                          : (on) => setState(() {
                                _chosenTouched = true;
                                on ? _chosen.add(c.id) : _chosen.remove(c.id);
                              }),
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
              if (_allDuplicates)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l.instructorResSuggestAllDuplicates,
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
