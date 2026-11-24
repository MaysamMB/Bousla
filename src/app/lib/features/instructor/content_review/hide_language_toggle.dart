import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Two checkboxes: hide the Arabic answers / hide the English answers from
/// students. [arabic] and [english] are null when mixed (the "all questions"
/// row). Ticking one unticks the other: students always see one language.
class HideLanguageToggles extends StatelessWidget {
  const HideLanguageToggles({
    super.key,
    required this.arabic,
    required this.english,
    required this.onChanged,
    this.forAllQuestions = false,
  });

  final bool? arabic;
  final bool? english;
  final void Function(Language language, bool hidden) onChanged;
  final bool forAllQuestions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 16,
      children: [
        _Toggle(
          key: ValueKey('hide-ar${forAllQuestions ? '-all' : ''}'),
          label: forAllQuestions
              ? l.reviewHideArabicOptionsAll
              : l.reviewHideArabicOptions,
          value: arabic,
          onChanged: (hidden) => onChanged(Language.ar, hidden),
        ),
        _Toggle(
          key: ValueKey('hide-en${forAllQuestions ? '-all' : ''}'),
          label: forAllQuestions
              ? l.reviewHideEnglishOptionsAll
              : l.reviewHideEnglishOptions,
          value: english,
          onChanged: (hidden) => onChanged(Language.en, hidden),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// Null shows a dash (some questions hidden, some not). Tapping then hides
  /// it everywhere.
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final next = value != true;
    return InkWell(
      onTap: () => onChanged(next),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            tristate: true,
            onChanged: (_) => onChanged(next),
          ),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}
