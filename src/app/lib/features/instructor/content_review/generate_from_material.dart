import 'package:bousla_engine/bousla_engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/ai/question_generator.dart';
import '../../../l10n/app_localizations.dart';

/// Picks a file; returns null when cancelled. Replaced in tests.
typedef PickMaterial = Future<MaterialFile?> Function();

/// What the dialog did, for the review screen's message.
class GenerationOutcome {
  const GenerationOutcome({
    required this.savedIds,
    required this.dropped,
    required this.materialName,
    required this.modelName,
    this.requested = 0,
    this.returned = 0,
    this.droppedReasons = const {},
  });

  /// How many questions the instructor asked for.
  final int requested;

  /// How many the model wrote (before the checks).
  final int returned;

  /// Dropped drafts per reason (DraftIssue name, or `app_checks`).
  final Map<String, int> droppedReasons;

  /// IDs of the drafts saved as pending review.
  final Set<String> savedIds;

  /// Drafts dropped by the automatic checks.
  final int dropped;
  final String materialName;
  final String modelName;

  int get saved => savedIds.length;
}

Future<MaterialFile?> pickMaterialFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'txt', 'md'],
  );
  if (file == null) return null;
  final mimeType = MaterialFile.mimeTypeFor(file.name);
  if (mimeType == null) {
    throw const QuestionGenerationException(GenerationProblem.unsupportedFile);
  }
  final length = await file.length();
  if (length != null && length > MaterialFile.maxBytes) {
    throw const QuestionGenerationException(GenerationProblem.fileTooLarge);
  }
  return MaterialFile(
    name: file.name,
    mimeType: mimeType,
    bytes: await file.readAsBytes(),
  );
}

/// AI level 1 (docs/architecture.md §4): the instructor picks their own
/// material, the model drafts bilingual questions, the engine's checks drop
/// unusable drafts, and the rest are saved as pending review. Nothing is
/// approved here; the review screen is where the instructor decides.
class GenerateFromMaterialDialog extends StatefulWidget {
  const GenerateFromMaterialDialog({
    super.key,
    required this.courseId,
    required this.concepts,
    this.pickMaterial = pickMaterialFile,
  });

  final String courseId;
  final List<Concept> concepts;
  final PickMaterial pickMaterial;

  @override
  State<GenerateFromMaterialDialog> createState() =>
      _GenerateFromMaterialDialogState();
}

class _GenerateFromMaterialDialogState
    extends State<GenerateFromMaterialDialog> {
  MaterialFile? _file;
  var _count = 5;
  var _busy = false;
  GenerationProblem? _problem;

  /// The server's own message, shown under ours so a setup problem can be
  /// diagnosed from a screenshot.
  String? _detail;

  /// Every draft was dropped by the checks (nothing to review).
  var _nothingUsable = false;

  List<Concept> get _approved => [
        for (final c in widget.concepts)
          if (c.status == ReviewStatus.approved) c,
      ];

  Future<void> _pick() async {
    setState(() {
      _problem = null;
      _nothingUsable = false;
    });
    try {
      final file = await widget.pickMaterial();
      if (file != null && mounted) setState(() => _file = file);
    } on QuestionGenerationException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    }
  }

  Future<void> _generate() async {
    final services = ServicesScope.of(context);
    final generator = services.questionGenerator!;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _problem = null;
      _detail = null;
      _nothingUsable = false;
    });
    try {
      final result = await generator.draftQuestions(
        material: _file!,
        concepts: _approved,
        count: _count,
      );
      final reasons = <String, int>{};
      for (final issue in result.dropped) {
        reasons[issue.name] = (reasons[issue.name] ?? 0) + 1;
      }
      final saved = await services.content.saveAiDrafts(
        widget.courseId,
        materialName: _file!.name,
        modelName: generator.modelName,
        drafts: result.accepted,
        droppedByChecks: result.dropped.length,
        requested: _count,
        droppedReasons: reasons,
      );
      final appSkipped = result.accepted.length - saved.length;
      if (saved.isEmpty) {
        if (mounted) setState(() => _nothingUsable = true);
        return;
      }
      navigator.pop(
        GenerationOutcome(
          savedIds: {for (final q in saved) q.id},
          dropped:
              result.dropped.length + result.accepted.length - saved.length,
          materialName: _file!.name,
          modelName: generator.modelName,
          requested: _count,
          returned: result.accepted.length +
              result.dropped.where((i) => i != DraftIssue.invalidJson).length,
          droppedReasons: {
            ...reasons,
            if (appSkipped > 0) 'app_checks': appSkipped,
          },
        ),
      );
    } on QuestionGenerationException catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.problem;
          _detail = e.detail;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _problem = GenerationProblem.unknown;
          _detail = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String problemText(AppLocalizations l, GenerationProblem p) =>
      switch (p) {
        GenerationProblem.notEnabled => l.reviewAiErrorNotEnabled,
        GenerationProblem.quota => l.reviewAiErrorQuota,
        GenerationProblem.busy => l.reviewAiErrorBusy,
        GenerationProblem.dailyQuota => l.reviewAiErrorDailyQuota,
        GenerationProblem.fileTooLarge => l.reviewAiErrorTooLarge,
        GenerationProblem.unsupportedFile => l.reviewAiErrorUnsupported,
        GenerationProblem.emptyAnswer => l.reviewAiErrorEmpty,
        GenerationProblem.network => l.reviewAiErrorNetwork,
        GenerationProblem.unknown => l.errorGeneric,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = _file;
    final noConcepts = _approved.isEmpty;
    return AlertDialog(
      title: Text(l.reviewAiDialogTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.reviewAiPrivacy, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              if (noConcepts)
                Text(
                  l.reviewAiNoConcepts,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(l.reviewAiPickFile),
                ),
                if (file != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.reviewAiFileChosen(
                      file.name,
                      (file.bytes.length / 1024).ceil(),
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                Text(l.reviewAiCount),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final n in const [3, 5, 10])
                      ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {_count},
                  onSelectionChanged:
                      _busy ? null : (v) => setState(() => _count = v.first),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l.reviewAiWorking, textAlign: TextAlign.center),
              ],
              if (_problem case final problem?) ...[
                const SizedBox(height: 12),
                Text(
                  problemText(l, problem),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                // Known problems have a clear message; the server's raw
                // text is only offered, folded, for unknown ones.
                if (_detail case final detail?
                    when problem == GenerationProblem.unknown)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      l.reviewAiTechnicalDetails,
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      Text(
                        detail.length > 300
                            ? '${detail.substring(0, 300)}…'
                            : detail,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
              if (_nothingUsable) ...[
                const SizedBox(height: 12),
                Text(
                  l.reviewAiNothingUsable,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
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
          onPressed: _busy || file == null || noConcepts ? null : _generate,
          child: Text(l.reviewAiStart),
        ),
      ],
    );
  }
}

/// Short reason text for a dropped draft (a [DraftIssue] name or
/// `app_checks`).
String droppedReasonText(AppLocalizations l, String reason) => switch (reason) {
      'unknownConcept' => l.reviewAiIssueUnknownConcept,
      'duplicate' => l.reviewAiIssueDuplicate,
      'optionsInPrompt' => l.reviewAiIssueOptionsInPrompt,
      'promptArabicMissing' ||
      'promptEnglishMissing' ||
      'promptArabicHasNoArabicLetters' ||
      'optionTextMissing' =>
        l.reviewAiIssueLanguage,
      'tooFewOptions' ||
      'tooManyOptions' ||
      'correctOptionMissing' =>
        l.reviewAiIssueOptions,
      _ => l.reviewAiIssueOther,
    };

/// "Asked 5 · Gemini wrote 3 · 2 saved · 1 dropped (duplicate)".
String generationSummary(AppLocalizations l, GenerationOutcome o) {
  final summary = l.reviewAiSummary(o.requested, o.returned, o.saved);
  if (o.droppedReasons.isEmpty) return summary;
  final byText = <String, int>{};
  for (final e in o.droppedReasons.entries) {
    final t = droppedReasonText(l, e.key);
    byText[t] = (byText[t] ?? 0) + e.value;
  }
  final reasons = [for (final e in byText.entries) '${e.key} ${e.value}'];
  return '$summary\n${l.reviewAiDroppedReasons(reasons.join(' · '))}';
}
