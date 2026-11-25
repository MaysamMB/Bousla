import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/language_switcher.dart';
import '../../shared/widgets/bousla_mark.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: WatermarkedBody(
        child: Align(
          // Lower half: the watermark sits in the empty space above.
          alignment: const Alignment(0, 0.5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.homeTagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/join'),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(l.homeJoin),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/instructor'),
                    icon: const Icon(Icons.school_outlined),
                    label: Text(l.homeInstructor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
