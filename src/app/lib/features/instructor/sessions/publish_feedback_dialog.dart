import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback_publisher.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import 'share_feedback.dart';

/// Opens the "Publish feedback" dialog for a closed [session]. Returns the
/// result when feedback was published, null when cancelled.
Future<PublishResult?> showPublishFeedbackDialog(
  BuildContext context,
  Session session,
) =>
    showDialog<PublishResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PublishFeedbackDialog(session: session),
    );

/// Confirms publication, with the option to add AI explanations. The option
/// is a choice for this publication only; it is not stored on the session.
/// Publishing always works without AI.
class PublishFeedbackDialog extends StatefulWidget {
  const PublishFeedbackDialog({super.key, required this.session});

  final Session session;

  @override
  State<PublishFeedbackDialog> createState() => _PublishFeedbackDialogState();
}

class _PublishFeedbackDialogState extends State<PublishFeedbackDialog> {
  var _useAi = true;
  var _busy = false;
  var _failed = false;
  PublishResult? _result;

  Future<void> _publish() async {
    // A second press while publishing does nothing.
    if (_busy) return;
    final services = ServicesScope.of(context);
    final aiAvailable = services.feedbackExplainer != null;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await FeedbackPublisher(
        content: services.content,
        sessions: services.sessions,
        explainer: services.feedbackExplainer,
      ).publish(widget.session, useAi: aiAvailable && _useAi);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = _result;
    final aiAvailable = ServicesScope.of(context).feedbackExplainer != null;

    if (result != null) {
      return AlertDialog(
        title: Text(l.instructorPublishDone(result.students)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.instructorPublishSummary(
                result.aiStudents,
                result.templateStudents,
                result.profiles,
              ),
            ),
            if (result.aiProblem != null) ...[
              const SizedBox(height: 8),
              Text(l.instructorPublishAiFailed),
            ],
            if (result.guardRejected > 0) ...[
              const SizedBox(height: 8),
              Text(l.instructorPublishGuardReplaced(result.guardRejected)),
            ],
            const SizedBox(height: 16),
            // Students cannot be notified: let the instructor send the link.
            ShareFeedbackButton(session: widget.session),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(result),
            child: Text(l.instructorPublishClose),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(l.instructorPublishDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorPublishDialogBody),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.instructorPublishAiOption),
              subtitle: Text(
                aiAvailable
                    ? l.instructorPublishAiOptionHint
                    : l.instructorPublishAiUnavailable,
              ),
              value: aiAvailable && _useAi,
              onChanged: aiAvailable && !_busy
                  ? (v) => setState(() => _useAi = v)
                  : null,
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                aiAvailable && _useAi
                    ? l.instructorPublishWorkingAi
                    : l.instructorPublishWorking,
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(
                l.instructorPublishError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.instructorPublishCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _publish,
          child: Text(l.instructorPublishConfirm),
        ),
      ],
    );
  }
}
