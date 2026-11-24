import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../answering/answering_screen.dart';
import '../knowledge_map/knowledge_map_view.dart';

/// A student's released feedback for one session (owner: student portal;
/// the content is Lina's task, docs/implementation-plan.md Phase 5).
///
/// Reached from the join screen when the session is closed and feedback is
/// released: a student coming back to the link later, from the same browser
/// (same anonymous account). Shows the knowledge map for now.
/// TODO(Lina): add the explanation (AI or template) and the next steps with
/// resources above the map.
class MyFeedbackScreen extends StatelessWidget {
  const MyFeedbackScreen({
    super.key,
    required this.session,
    required this.participantId,
  });

  final Session session;
  final String participantId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sessions = ServicesScope.of(context).sessions;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentFeedbackTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: StreamBuilder<StudentFeedback?>(
        stream: sessions
            .watchMyFeedback(session.id, participantId)
            .timeout(AnsweringScreen.timeout),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              snapshot.error is TimeoutException
                  ? l.studentConnectionSlow
                  : l.errorGeneric,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final feedback = snapshot.data;
          // Released, but nothing for this account: did not answer in this
          // session, or answered from another phone or browser.
          if (feedback == null) return _Message(l.studentFeedbackNone);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [KnowledgeMapView(feedback: feedback)],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
