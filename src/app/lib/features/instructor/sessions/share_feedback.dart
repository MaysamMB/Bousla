import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/open_link.dart';
import '../../../shared/share_text.dart';

/// Students have no account, email or phone number in Bousla, so the app
/// cannot notify them. After publishing, the instructor can send the class
/// the session's link and code instead (WhatsApp, Classroom, mail…). The
/// message is in Arabic and English, since a class mixes both, and says to
/// open the link on the phone and browser the student answered from: that
/// is where their feedback is.
String shareFeedbackMessage(Session session, {String? link}) {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  String part(AppLocalizations l, String? title) => [
        if (title != null && title.trim().isNotEmpty) '«${title.trim()}»',
        l.instructorShareMessage(session.code),
        if (link != null) link,
      ].join('\n');
  return '${part(ar, session.title?.ar)}\n\n${part(en, session.title?.en)}';
}

/// The link students use to come back to [session] (web only).
String? sessionJoinLink(Session session) =>
    kIsWeb ? '${Uri.base.origin}/#/join/${session.code}' : null;

/// "Share with students": the message, and ways to send it.
class ShareFeedbackButton extends StatelessWidget {
  const ShareFeedbackButton({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => ShareFeedbackSheet(session: session),
        ),
        icon: const Icon(Icons.share_outlined),
        label: Text(AppLocalizations.of(context).instructorShareFeedback),
      );
}

class ShareFeedbackSheet extends StatelessWidget {
  const ShareFeedbackSheet({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final link = sessionJoinLink(session);
    final message = shareFeedbackMessage(session, link: link);
    final messenger = ScaffoldMessenger.of(context);
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(SnackBar(content: Text(l.instructorShareCopied)));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorShareFeedback, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.instructorShareHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message,
                key: const ValueKey('share-message'),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (link != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink(
                      'https://classroom.google.com/share?url='
                      '${Uri.encodeQueryComponent(link)}',
                    ),
                    icon: const Icon(Icons.school_outlined),
                    label: Text(l.instructorShareClassroom),
                  ),
                OutlinedButton.icon(
                  onPressed: copy,
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(l.instructorShareCopy),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    // The phone's share sheet; copy where there is none.
                    if (!await shareText(text: message)) await copy();
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l.instructorShareSend),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
