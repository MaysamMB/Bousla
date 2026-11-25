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
        TextButton.icon(
          onPressed: services.toggleLanguage,
          icon: const Icon(Icons.translate),
          label: Text(l.languageToggle),
        ),
      ],
    );
  }
}
