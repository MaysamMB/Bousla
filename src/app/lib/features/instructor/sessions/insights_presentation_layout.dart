import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// A presentation-friendly view of the same live evidence, not a new screen
/// or a new request. Detailed charts and AI drafts are hidden by the caller.
class InsightsPresentationLayout extends StatefulWidget {
  const InsightsPresentationLayout({super.key, required this.builder});

  final Widget Function(BuildContext context, bool presentationMode) builder;

  @override
  State<InsightsPresentationLayout> createState() =>
      _InsightsPresentationLayoutState();
}

class _InsightsPresentationLayoutState extends State<InsightsPresentationLayout> {
  bool _presentationMode = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.instructorPresentationTitle),
          subtitle: Text(l.instructorPresentationHint),
          secondary: const Icon(Icons.co_present),
          value: _presentationMode,
          onChanged: (value) => setState(() => _presentationMode = value),
        ),
        Theme(
          data: _presentationMode
              ? theme.copyWith(textTheme: theme.textTheme.apply(fontSizeFactor: 1.2))
              : theme,
          child: Builder(
            builder: (context) => widget.builder(context, _presentationMode),
          ),
        ),
      ],
    );
  }
}
