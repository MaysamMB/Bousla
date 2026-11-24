import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../course_picker.dart';
import 'live_insights_panel.dart';
import 'publish_feedback_dialog.dart';

/// Keeps a code left-to-right inside an Arabic sentence (Unicode isolate),
/// without turning the whole sentence around.
String _ltr(String code) => '\u2066$code\u2069';

/// "When" for a session: its date and time in the UI language.
String sessionWhen(BuildContext context, DateTime? at) {
  if (at == null) return '';
  final ml = MaterialLocalizations.of(context);
  final local = at.toLocal();
  return '${ml.formatMediumDate(local)} · '
      '${TimeOfDay.fromDateTime(local).format(context)}';
}

/// The title of [s] in the UI language, or a fallback for older sessions.
String sessionTitleText(BuildContext context, Session s) =>
    s.title?.of(currentLanguage(context)) ??
    AppLocalizations.of(context).instructorSessionFallbackTitle(s.code);

/// The instructor's sessions of the chosen course, newest first. Each opens
/// its results, computed again from the stored answers.
class PastSessionsScreen extends StatefulWidget {
  const PastSessionsScreen({super.key});

  @override
  State<PastSessionsScreen> createState() => _PastSessionsScreenState();
}

class _PastSessionsScreenState extends State<PastSessionsScreen> {
  Future<List<Session>>? _sessions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessions ??= _load();
  }

  Future<List<Session>> _load() async {
    final services = ServicesScope.of(context);
    final owner = services.auth.instructorId;
    final course = chooseCourse(
      await services.content.listCourses(),
      services.selectedCourseId.value,
    );
    if (owner == null || course == null) return const [];
    return services.sessions.listSessions(ownerId: owner, courseId: course.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.instructorPastSessions),
        actions: const [LanguageSwitcher()],
      ),
      body: FutureBuilder<List<Session>>(
        future: _sessions,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(l.errorGeneric));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.instructorPastEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sessions.length,
                itemBuilder: (context, i) => _SessionTile(
                  session: sessions[i],
                  // A rename on the results page shows here too.
                  onChanged: () => setState(() {
                    _sessions = _load();
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Open, closed, or closed with feedback published: a word and an icon.
Widget sessionStatusChip(BuildContext context, Session s) {
  final l = AppLocalizations.of(context);
  final (icon, label) = switch (s) {
    Session(status: SessionStatus.open) => (
        Icons.radio_button_checked,
        l.instructorSessionStatusOpen,
      ),
    Session(feedbackReleased: true) => (
        Icons.mark_email_read_outlined,
        l.instructorSessionStatusReleased,
      ),
    _ => (Icons.lock_outline, l.instructorSessionStatusClosed),
  };
  return Chip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onChanged});

  final Session session;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        title: Text(sessionTitleText(context, session)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(sessionWhen(context, session.createdAt)),
              Text(l.instructorJoinCode(_ltr(session.code))),
              sessionStatusChip(context, session),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final renamed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => PastSessionScreen(session: session),
            ),
          );
          if (renamed == true) onChanged();
        },
      ),
    );
  }
}

/// One past session: when, how many took part, and the class results
/// (the live insights panel, which recomputes them from the stored answers;
/// aggregated, small groups hidden).
class PastSessionScreen extends StatefulWidget {
  const PastSessionScreen({super.key, required this.session});

  final Session session;

  @override
  State<PastSessionScreen> createState() => _PastSessionScreenState();
}

class _PastSessionScreenState extends State<PastSessionScreen> {
  late Session session = widget.session;
  var _changed = false;

  Future<void> _rename() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final title = await showDialog<LocalizedText>(
      context: context,
      builder: (_) => _RenameDialog(
        initial: session.title ??
            LocalizedText(
              ar: l.instructorSessionFallbackTitle(session.code),
              en: l.instructorSessionFallbackTitle(session.code),
            ),
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ServicesScope.of(context).sessions.renameSession(session.id, title);
      setState(() {
        session = session.copyWith(title: title);
        _changed = true;
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
  }

  /// An old session left open (e.g. after leaving the page) can be closed
  /// here, so students can no longer answer it.
  Future<void> _close() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sessions = ServicesScope.of(context).sessions;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.instructorCloseSession),
        content: Text(l.instructorCloseConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.reviewCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.instructorCloseSession),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await sessions.closeSession(session.id);
      setState(() {
        session = session.copyWith(
          status: SessionStatus.closed,
          closedAt: DateTime.now(),
        );
        _changed = true;
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
  }

  /// A closed session whose feedback was never published: publish it now
  /// (the same dialog as on the session screen).
  Future<void> _publish() async {
    final result = await showPublishFeedbackDialog(context, session);
    if (result == null || !mounted) return;
    setState(() {
      session = session.copyWith(feedbackReleased: true);
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sessions = ServicesScope.of(context).sessions;
    // Back tells the list whether to reload.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.instructorPastSessionTitle),
          actions: const [LanguageSwitcher()],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sessionTitleText(context, session),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l.instructorRenameSession,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _rename,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(sessionWhen(context, session.createdAt)),
                    Text(l.instructorJoinCode(_ltr(session.code))),
                    sessionStatusChip(context, session),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<Response>>(
                  stream: sessions.watchResponses(session.id),
                  builder: (context, snapshot) {
                    final responses = snapshot.data ?? const <Response>[];
                    final participants =
                        responses.map((r) => r.participantId).toSet().length;
                    return Text(
                      l.instructorLiveCounts(participants, responses.length),
                    );
                  },
                ),
                const SizedBox(height: 24),
                if (session.status == SessionStatus.closed &&
                    !session.feedbackReleased) ...[
                  FilledButton.icon(
                    onPressed: _publish,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(l.instructorPublishFeedback),
                  ),
                  const SizedBox(height: 24),
                ],
                if (session.status == SessionStatus.open) ...[
                  OutlinedButton.icon(
                    onPressed: _close,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(l.instructorCloseSession),
                  ),
                  const SizedBox(height: 24),
                ],
                LiveInsightsPanel(session: session),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two fields, Arabic and English. If one is left empty, the other is used
/// for both; both empty cannot be saved.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final LocalizedText initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _ar = TextEditingController(text: widget.initial.ar);
  late final _en = TextEditingController(text: widget.initial.en);

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  LocalizedText? get _value {
    final ar = _ar.text.trim();
    final en = _en.text.trim();
    if (ar.isEmpty && en.isEmpty) return null;
    return LocalizedText(
      ar: ar.isEmpty ? en : ar,
      en: en.isEmpty ? ar : en,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.instructorRenameSession),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ar,
              maxLength: maxSessionTitleLength,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(labelText: l.instructorTitleArabic),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _en,
              maxLength: maxSessionTitleLength,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.instructorTitleEnglish),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.reviewCancel),
        ),
        FilledButton(
          onPressed:
              _value == null ? null : () => Navigator.of(context).pop(_value),
          child: Text(l.instructorRenameSave),
        ),
      ],
    );
  }
}
