import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/text_direction.dart';
import '../../../shared/widgets/language_switcher.dart';

/// A course outline the student chose: name and size only. The bytes are
/// not kept: nothing is sent or stored in this preview.
class PickedOutline {
  const PickedOutline({required this.name, required this.bytes});

  final String name;
  final int bytes;
}

Future<PickedOutline?> pickOutlineFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'txt', 'md', 'docx'],
  );
  if (file == null) return null;
  return PickedOutline(name: file.name, bytes: await file.length() ?? 0);
}

/// "Add a course from outside Bousla" (career path, next step; design doc
/// "تصميم المسار المهني"). **Front end only**: the student names the course
/// and picks or pastes its outline, and sees what will happen next (topics
/// extracted, confirmed by the student, an AI self-check, a comparison with
/// the job market). Continuing says plainly that this step is not built yet;
/// no file or text leaves the device and nothing is saved.
class ExternalCourseScreen extends StatefulWidget {
  const ExternalCourseScreen({super.key, this.pickOutline = pickOutlineFile});

  /// Replaced in tests.
  final Future<PickedOutline?> Function() pickOutline;

  @override
  State<ExternalCourseScreen> createState() => _ExternalCourseScreenState();
}

class _ExternalCourseScreenState extends State<ExternalCourseScreen> {
  final _name = TextEditingController();
  final _where = TextEditingController();
  final _pasted = TextEditingController();
  PickedOutline? _file;
  var _triedContinue = false;

  @override
  void dispose() {
    _name.dispose();
    _where.dispose();
    _pasted.dispose();
    super.dispose();
  }

  bool get _hasOutline => _file != null || _pasted.text.trim().isNotEmpty;
  bool get _ready => _name.text.trim().isNotEmpty && _hasOutline;

  Future<void> _pick() async {
    final picked = await widget.pickOutline();
    if (picked != null && mounted) setState(() => _file = picked);
  }

  Future<void> _continue() async {
    setState(() => _triedContinue = true);
    if (!_ready) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('external-not-ready'),
        icon: const Icon(Icons.construction_outlined),
        title: Text(l.studentExternalNotReadyTitle),
        content: Text(l.studentExternalNotReadyBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.studentExternalOk),
          ),
        ],
      ),
    );
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: scheme.primaryContainer,
                child: Text('$n',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentExternalTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                key: const ValueKey('external-preview-notice'),
                color: scheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: scheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l.studentExternalPreviewNotice,
                            style:
                                TextStyle(color: scheme.onTertiaryContainer)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.studentExternalIntro),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('external-name'),
                controller: _name,
                textDirection: textDirectionOf(_name.text),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.studentExternalNameLabel,
                  hintText: l.studentExternalNameHint,
                  errorText: _triedContinue && _name.text.trim().isEmpty
                      ? l.studentExternalNameMissing
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('external-where'),
                controller: _where,
                textDirection: textDirectionOf(_where.text),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.studentExternalWhereLabel,
                  hintText: l.studentExternalWhereHint,
                ),
              ),
              const SizedBox(height: 20),
              Text(l.studentExternalOutlineTitle,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l.studentExternalOutlineHint,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('external-pick'),
                onPressed: _pick,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_file == null
                    ? l.studentExternalPick
                    : l.studentExternalPickAnother),
              ),
              if (_file != null)
                ListTile(
                  key: const ValueKey('external-file'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_file!.name),
                  subtitle: Text(_size(_file!.bytes)),
                  trailing: IconButton(
                    tooltip: l.studentExternalRemoveFile,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _file = null),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('external-paste'),
                controller: _pasted,
                minLines: 3,
                maxLines: 8,
                textDirection: textDirectionOf(_pasted.text),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.studentExternalPasteLabel,
                  alignLabelWithHint: true,
                  errorText: _triedContinue && !_hasOutline
                      ? l.studentExternalOutlineMissing
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              Text(l.studentExternalStepsTitle,
                  style: theme.textTheme.titleSmall),
              step(1, l.studentExternalStep1),
              step(2, l.studentExternalStep2),
              step(3, l.studentExternalStep3),
              step(4, l.studentExternalStep4),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('external-continue'),
                onPressed: _continue,
                icon: const Icon(Icons.arrow_forward),
                label: Text(l.studentExternalContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
