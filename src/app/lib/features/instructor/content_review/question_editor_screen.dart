import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../data/question_review.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'hide_language_toggle.dart';
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

final _arabicLetter = RegExp(r'[؀-ۿ]');

bool _isArabic(String text) => _arabicLetter.hasMatch(text);

/// One answer: the text in any language, and its optional translation.
class _OptionFields {
  _OptionFields(this.id, {String main = '', String translation = ''})
    : main = TextEditingController(text: main),
      translation = TextEditingController(text: translation);

  final String id;
  final TextEditingController main;
  final TextEditingController translation;

  void dispose() {
    main.dispose();
    translation.dispose();
  }
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  /// The question as the instructor writes it, in any language.
  late final TextEditingController _prompt;

  /// The optional translation, into the other language.
  late final TextEditingController _promptTranslation;
  late final List<_OptionFields> _options;

  /// The translation fields are shown. Without a translation, the same text
  /// is stored for Arabic and English and students see it as written.
  late bool _translate;

  /// The concept chosen in the dropdown, plus any further concepts the
  /// question already had (kept unchanged).
  String? _conceptId;
  late final List<String> _otherConcepts;
  String? _correct;

  /// Languages whose answers students do not see; the text is still
  /// required in both.
  late Set<Language> _hidden;
  var _problems = <DraftProblem>[];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    // A question written in one language has the same text in both.
    final single = q == null ||
        (q.prompt.ar.trim() == q.prompt.en.trim() &&
            q.options.every((o) => o.text.ar.trim() == o.text.en.trim()));
    _translate = !single;
    _prompt = TextEditingController(text: q?.prompt.ar ?? '');
    _promptTranslation =
        TextEditingController(text: single ? '' : q.prompt.en);
    _options = q == null
        ? [_OptionFields('a'), _OptionFields('b')]
        : [
            for (final o in q.options)
              _OptionFields(
                o.id,
                main: o.text.ar,
                translation: single ? '' : o.text.en,
              ),
          ];
    // Directions follow the text typed, so refresh on every change.
    for (final c in [_prompt, _promptTranslation]) {
      c.addListener(_refresh);
    }
    final known = {for (final c in widget.concepts) c.id};
    final first = q?.conceptIds.firstOrNull;
    // The dropdown only accepts approved concepts.
    _conceptId = first != null && known.contains(first) ? first : null;
    _otherConcepts = q == null ? [] : q.conceptIds.skip(1).toList();
    _correct = widget.correctOptionId;
    _hidden = Set.of(q?.hiddenOptionLanguages ?? const <Language>{});
  }

  @override
  void dispose() {
    _prompt.dispose();
    _promptTranslation.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// The main text is Arabic when it has Arabic letters; the translation is
  /// then the English, and the other way round.
  bool get _mainIsArabic => _isArabic(_prompt.text);

  /// Both languages from a main text and its translation. Without a
  /// translation (or an empty one), the main text is used for both.
  LocalizedText _pair(String main, String translation) {
    final t = translation.trim();
    if (!_translate || t.isEmpty) return LocalizedText(ar: main, en: main);
    return _mainIsArabic
        ? LocalizedText(ar: main, en: translation)
        : LocalizedText(ar: translation, en: main);
  }

  QuestionDraft _draft() => QuestionDraft(
    id: widget.question?.id,
    conceptIds: [if (_conceptId != null) _conceptId!, ..._otherConcepts],
    prompt: _pair(_prompt.text, _promptTranslation.text),
    options: [
      for (final o in _options)
        OptionView(id: o.id, text: _pair(o.main.text, o.translation.text)),
    ],
    correctOptionId: _correct,
    // Hiding one language only makes sense with a translation.
    hiddenOptionLanguages: _translate ? _hidden : const {},
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
    // Until something is typed, assume the interface language.
    final mainArabic = _prompt.text.trim().isEmpty
        ? language == Language.ar
        : _mainIsArabic;
    final translationLabel = mainArabic
        ? l.reviewEditorTranslationEn
        : l.reviewEditorTranslationAr;

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
                key: const ValueKey('prompt'),
                controller: _prompt,
                label: l.reviewEditorPrompt,
                helper: l.reviewEditorPromptHint,
                minLines: 2,
              ),
              if (_translate) ...[
                const SizedBox(height: 12),
                _BilingualField(
                  key: const ValueKey('prompt-translation'),
                  controller: _promptTranslation,
                  label: translationLabel,
                  minLines: 2,
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('translate'),
                  onPressed: () => setState(() => _translate = !_translate),
                  icon: Icon(_translate ? Icons.close : Icons.translate),
                  label: Text(
                    _translate
                        ? l.reviewEditorRemoveTranslation
                        : l.reviewEditorAddTranslation,
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
              if (_translate) ...[
              const SizedBox(height: 12),
              HideLanguageToggles(
                arabic: _hidden.contains(Language.ar),
                english: _hidden.contains(Language.en),
                onChanged: (language, hidden) => setState(
                  () => _hidden = toggleHiddenLanguage(
                    _hidden,
                    language,
                    hidden,
                  ),
                ),
              ),
              Text(
                l.reviewHiddenOptionsHint,
                style: theme.textTheme.bodySmall,
              ),
              ],
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
                          key: ValueKey('option-${_options[i].id}'),
                          controller: _options[i].main,
                          label: l.reviewEditorOptionText,
                        ),
                        if (_translate) ...[
                          const SizedBox(height: 8),
                          _BilingualField(
                            key: ValueKey('option-${_options[i].id}-translation'),
                            controller: _options[i].translation,
                            label: translationLabel,
                          ),
                        ],
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

/// A text field whose direction follows what is typed (Arabic letters:
/// right-to-left), not the UI language.
class _BilingualField extends StatefulWidget {
  const _BilingualField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.minLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final int minLines;

  @override
  State<_BilingualField> createState() => _BilingualFieldState();
}

class _BilingualFieldState extends State<_BilingualField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return TextField(
      controller: widget.controller,
      textDirection: text.trim().isEmpty
          ? null
          : _isArabic(text)
              ? TextDirection.rtl
              : TextDirection.ltr,
      minLines: widget.minLines,
      maxLines: null,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
