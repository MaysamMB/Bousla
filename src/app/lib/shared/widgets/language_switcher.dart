import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../l10n/app_localizations.dart';

/// App bar button that switches between Arabic and English.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: ServicesScope.of(context).toggleLanguage,
      icon: const Icon(Icons.translate),
      label: Text(AppLocalizations.of(context).languageToggle),
    );
  }
}
