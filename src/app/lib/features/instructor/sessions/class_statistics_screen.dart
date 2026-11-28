import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'live_insights_panel.dart';

/// The class statistics of one session on their own page, opened from the
/// session screen's "Class statistics" button. It shows the existing
/// [LiveInsightsPanel] unchanged: same data source, same calculations, same
/// privacy threshold. The panel reads the session's answers only while this
/// page is open. Back returns to the session screen.
class ClassStatisticsScreen extends StatelessWidget {
  const ClassStatisticsScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.instructorClassStats),
        actions: const [LanguageSwitcher()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [LiveInsightsPanel(session: session)],
      ),
    );
  }
}
