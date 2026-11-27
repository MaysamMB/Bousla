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

/// The invitation to join [session] while it is open: its title, code and
/// link, in Arabic and English (a class mixes both).
String shareJoinMessage(Session session, {String? link}) {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  String part(AppLocalizations l, String? title) => [
        if (title != null && title.trim().isNotEmpty) '«${title.trim()}»',
        l.instructorShareJoinMessage(session.code),
        if (link != null) link,
      ].join('\n');
  return '${part(ar, session.title?.ar)}\n\n${part(en, session.title?.en)}';
}

/// "Share the session": the join code and link, to post where the class
/// already talks (WhatsApp, Classroom…), next to the QR code.
class ShareJoinButton extends StatelessWidget {
  const ShareJoinButton({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OutlinedButton.icon(
      key: const ValueKey('share-join'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ShareFeedbackSheet(
          session: session,
          title: l.instructorShareJoin,
          hint: l.instructorShareJoinHint,
          message: shareJoinMessage(session, link: sessionJoinLink(session)),
        ),
      ),
      icon: const Icon(Icons.share_outlined),
      label: Text(l.instructorShareJoin),
    );
  }
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
  const ShareFeedbackSheet({
    super.key,
    required this.session,
    this.title,
    this.hint,
    this.message,
  });

  final Session session;

  /// The sheet shares the feedback message unless these are given (the
  /// join invitation uses the same sheet).
  final String? title;
  final String? hint;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final link = sessionJoinLink(session);
    final message =
        this.message ?? shareFeedbackMessage(session, link: link);
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
            Text(title ?? l.instructorShareFeedback,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(hint ?? l.instructorShareHint,
                style: theme.textTheme.bodySmall),
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
