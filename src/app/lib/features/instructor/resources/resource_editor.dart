import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/repositories/content_repository.dart';
import '../../../data/resource_review.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import 'resources_screen.dart' show resourceLanguageText, resourceTypeText;

/// Adds a resource, edits one, or completes an AI suggestion with its link.
/// The title is one text box in any language. Saving approves the resource
/// and pops it; nothing is saved on cancel.
class ResourceEditor extends StatefulWidget {
  const ResourceEditor({
    super.key,
    required this.courseId,
    required this.concepts,
    this.resource,
  });

  final String courseId;

  /// Approved concepts the resource can be linked to.
  final List<Concept> concepts;

  /// Null for a new resource.
  final Resource? resource;

  @override
  State<ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends State<ResourceEditor> {
  late final TextEditingController _title;
  late final TextEditingController _url;
  late ResourceType _type;
  late ResourceLanguage _language;
  late Set<String> _concepts;

  /// The language follows the title until the instructor picks one.
  late bool _languageChosen;
  String? _initialTitle;
  List<ResourceDraftIssue> _issues = const [];
  var _busy = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final r = widget.resource;
    _type = r?.type ?? ResourceType.video;
    _language = r?.language ?? ResourceLanguage.ar;
    _languageChosen = r != null;
    _concepts = {...?r?.conceptIds};
    _url = TextEditingController(text: r?.url ?? '');
    _title = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialTitle == null) {
      _initialTitle = widget.resource?.title.of(currentLanguage(context)) ?? '';
      _title.text = _initialTitle!;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  ResourceDraft get _draft => ResourceDraft(
        id: widget.resource?.id,
        conceptIds: _concepts.toList(),
        type: _type,
        language: _language,
        titleText: _title.text,
        url: _url.text,
        // An unchanged AI title keeps both its languages.
        keepTitle: _title.text.trim() == _initialTitle?.trim()
            ? widget.resource?.title
            : null,
      );

  Future<void> _save() async {
    final approved = {for (final c in widget.concepts) c.id};
    final issues = validateResourceDraft(_draft, approved);
    setState(() {
      _issues = issues;
      _failed = false;
    });
    if (issues.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await ServicesScope.of(context)
          .content
          .saveResource(widget.courseId, _draft);
      if (mounted) Navigator.of(context).pop(saved);
    } on InvalidResourceException catch (e) {
      if (mounted) setState(() => _issues = e.issues);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _error(AppLocalizations l, List<ResourceDraftIssue> mine) {
    final found = _issues.where(mine.contains).firstOrNull;
    return switch (found) {
      null => null,
      ResourceDraftIssue.noConcept => l.instructorResErrConcept,
      ResourceDraftIssue.titleMissing => l.instructorResErrTitle,
      ResourceDraftIssue.urlMissing => l.instructorResErrUrl,
      ResourceDraftIssue.urlInvalid => l.instructorResErrUrlInvalid,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    final theme = Theme.of(context);
    final r = widget.resource;
    final completing = r != null && r.status == ReviewStatus.pendingReview;
    final conceptError = _error(l, const [ResourceDraftIssue.noConcept]);
    return AlertDialog(
      title: Text(
        r == null
            ? l.instructorResAdd
            : completing
                ? l.instructorResAddLink
                : l.reviewEdit,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (completing && r.description != null) ...[
                Text(
                  r.description!.of(lang),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: l.instructorResFieldTitle,
                  helperText: l.instructorResFieldTitleHint,
                  errorText: _error(l, const [ResourceDraftIssue.titleMissing]),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (text) {
                  if (!_languageChosen && text.trim().isNotEmpty) {
                    setState(() => _language = guessResourceLanguage(text));
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(l.instructorResFieldType),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in ResourceType.values)
                    ChoiceChip(
                      label: Text(resourceTypeText(l, t)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: _type == ResourceType.activity
                      ? l.instructorResFieldUrlOptional
                      : l.instructorResFieldUrl,
                  hintText: 'https://',
                  hintTextDirection: TextDirection.ltr,
                  errorText: _error(l, const [
                    ResourceDraftIssue.urlMissing,
                    ResourceDraftIssue.urlInvalid,
                  ]),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.instructorResFieldLanguage),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in ResourceLanguage.values)
                    ChoiceChip(
                      label: Text(resourceLanguageText(l, g)),
                      selected: _language == g,
                      onSelected: (_) => setState(() {
                        _language = g;
                        _languageChosen = true;
                      }),
                    ),
                ],
              ),
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
                      selected: _concepts.contains(c.id),
                      onSelected: (on) => setState(
                        () => on ? _concepts.add(c.id) : _concepts.remove(c.id),
                      ),
                    ),
                ],
              ),
              if (conceptError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    conceptError,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l.errorGeneric,
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
          onPressed: _busy ? null : _save,
          child: Text(l.instructorResSaveApprove),
        ),
      ],
    );
  }
}
