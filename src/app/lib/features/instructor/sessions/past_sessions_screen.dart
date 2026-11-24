import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../course_picker.dart';
import 'live_insights_panel.dart';

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
                itemBuilder: (context, i) => _SessionTile(session: sessions[i]),
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
  const _SessionTile({required this.session});

  final Session session;

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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PastSessionScreen(session: session),
          ),
        ),
      ),
    );
  }
}

/// One past session: when, how many took part, and the class results
/// (the live insights panel, which recomputes them from the stored answers;
/// aggregated, small groups hidden).
class PastSessionScreen extends StatelessWidget {
  const PastSessionScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sessions = ServicesScope.of(context).sessions;
    return Scaffold(
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
              Text(
                sessionTitleText(context, session),
                style: theme.textTheme.headlineSmall,
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
              LiveInsightsPanel(session: session),
            ],
          ),
        ),
      ),
    );
  }
}
