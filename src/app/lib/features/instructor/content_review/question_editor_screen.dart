import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../data/question_review.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'review_texts.dart';

/// Add a question by hand ([question] is null) or edit an existing one,
/// including an AI draft. Pops `true` after saving.
class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({
    super.key,
    required this.courseId,
    required this.concepts,
    this.question,
    this.correctOptionId,
  });

  final String courseId;

  /// Approved concepts the question can be linked to.
  final List<Concept> concepts;
  final QuestionView? question;
  final String? correctOptionId;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _OptionFields {
  _OptionFields(this.id, {String ar = '', String en = ''})
    : ar = TextEditingController(text: ar),
      en = TextEditingController(text: en);

  final String id;
  final TextEditingController ar;
  final TextEditingController en;

  void dispose() {
    ar.dispose();
    en.dispose();
  }
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late final TextEditingController _promptAr;
  late final TextEditingController _promptEn;
  late final List<_OptionFields> _options;

  /// The concept chosen in the dropdown, plus any further concepts the
  /// question already had (kept unchanged).
  String? _conceptId;
  late final List<String> _otherConcepts;
  String? _correct;
  var _problems = <DraftProblem>[];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _promptAr = TextEditingController(text: q?.prompt.ar ?? '');
    _promptEn = TextEditingController(text: q?.prompt.en ?? '');
    _options = q == null
        ? [_OptionFields('a'), _OptionFields('b')]
        : [
            for (final o in q.options)
              _OptionFields(o.id, ar: o.text.ar, en: o.text.en),
          ];
    final known = {for (final c in widget.concepts) c.id};
    final first = q?.conceptIds.firstOrNull;
    // The dropdown only accepts approved concepts.
    _conceptId = first != null && known.contains(first) ? first : null;
    _otherConcepts = q == null ? [] : q.conceptIds.skip(1).toList();
    _correct = widget.correctOptionId;
  }

  @override
  void dispose() {
    _promptAr.dispose();
    _promptEn.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  QuestionDraft _draft() => QuestionDraft(
    id: widget.question?.id,
    conceptIds: [if (_conceptId != null) _conceptId!, ..._otherConcepts],
    prompt: LocalizedText(ar: _promptAr.text, en: _promptEn.text),
    options: [
      for (final o in _options)
        OptionView(
          id: o.id,
          text: LocalizedText(ar: o.ar.text, en: o.en.text),
        ),
    ],
    correctOptionId: _correct,
  );

  void _addOption() => setState(
    () => _options.add(_OptionFields(nextOptionId(_options.map((o) => o.id)))),
  );

  void _removeOption(int index) => setState(() {
    final removed = _options.removeAt(index);
    if (_correct == removed.id) _correct = null;
    removed.dispose();
  });

  Future<void> _save({required bool approve}) async {
    final draft = _draft();
    final problems = validateDraft(draft, {
      for (final c in widget.concepts) c.id,
    });
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    final repo = ServicesScope.of(context).content;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _problems = [];
      _busy = true;
    });
    try {
      await repo.saveQuestion(
        widget.courseId,
        draft,
        status: approve ? ReviewStatus.approved : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on InvalidDraftException catch (e) {
      if (mounted) setState(() => _problems = e.problems);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = currentLanguage(context);
    final q = widget.question;
    final location = q?.sourceLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(q == null ? l.reviewEditorNewTitle : l.reviewEditorEditTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (q != null && q.status == ReviewStatus.approved) ...[
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l.reviewEditorNewVersionNote),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (location != null) ...[
                Text(
                  l.reviewSourceLocation(location),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              _BilingualField(
                controller: _promptAr,
                label: l.reviewEditorPromptAr,
                direction: TextDirection.rtl,
                minLines: 2,
              ),
              const SizedBox(height: 12),
              _BilingualField(
                controller: _promptEn,
                label: l.reviewEditorPromptEn,
                direction: TextDirection.ltr,
                minLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _conceptId,
                decoration: InputDecoration(
                  labelText: l.reviewEditorConcept,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final c in widget.concepts)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name.of(language)),
                    ),
                ],
                onChanged: (value) => setState(() => _conceptId = value),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _options.length; i++)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.reviewEditorOption(_options[i].id),
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            ChoiceChip(
                              label: Text(l.reviewCorrectAnswer),
                              selected: _correct == _options[i].id,
                              onSelected: (_) =>
                                  setState(() => _correct = _options[i].id),
                            ),
                            IconButton(
                              tooltip: l.reviewEditorRemoveOption,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _options.length > minOptions
                                  ? () => _removeOption(i)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _BilingualField(
                          controller: _options[i].ar,
                          label: l.reviewEditorOptionAr,
                          direction: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        _BilingualField(
                          controller: _options[i].en,
                          label: l.reviewEditorOptionEn,
                          direction: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
              if (_options.length < maxOptions)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: Text(l.reviewEditorAddOption),
                  ),
                ),
              const SizedBox(height: 12),
              for (final p in _problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    draftProblemText(l, p),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _save(approve: false),
                    child: Text(l.reviewEditorSave),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _save(approve: true),
                    child: Text(l.reviewEditorSaveApprove),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text field whose direction follows its language, not the UI language,
/// so Arabic text stays right-to-left even in the English interface.
class _BilingualField extends StatelessWidget {
  const _BilingualField({
    required this.controller,
    required this.label,
    required this.direction,
    this.minLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextDirection direction;
  final int minLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textDirection: direction,
    minLines: minLines,
    maxLines: null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
