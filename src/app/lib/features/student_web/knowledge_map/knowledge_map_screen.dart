import 'package:flutter/material.dart';

import '../../../data/feedback.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'knowledge_map_view.dart';

/// The knowledge map on its own page, opened from the feedback screen
/// ("show my knowledge map"), so the feedback page stays short.
class KnowledgeMapScreen extends StatelessWidget {
  const KnowledgeMapScreen({super.key, required this.feedback});

  final StudentFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentMapScreenTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [KnowledgeMapView(feedback: feedback)],
          ),
        ),
      ),
    );
  }
}
