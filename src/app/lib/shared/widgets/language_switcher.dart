import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../l10n/app_localizations.dart';

/// App bar buttons: light/dark, then Arabic/English. Every screen shows
/// this in its app bar, so both choices are always one tap away.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final l = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: dark ? l.themeLight : l.themeDark,
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: services.toggleThemeMode,
        ),
        // On a phone the icon alone (the language is its tooltip and
        // screen-reader label), so the app bar keeps room for the title.
        if (MediaQuery.sizeOf(context).width < 600)
          IconButton(
            tooltip: l.languageToggle,
            icon: const Icon(Icons.translate),
            color: Theme.of(context).colorScheme.primary,
            onPressed: services.toggleLanguage,
          )
        else
          TextButton.icon(
            onPressed: services.toggleLanguage,
            icon: const Icon(Icons.translate),
            label: Text(l.languageToggle),
          ),
      ],
    );
  }
}
