import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import 'join_qr.dart';

/// Skeleton for the instructor flow (owner: instructor app).
///
/// Already works with the in-memory repositories: creates a session from all
/// approved questions of the first course, shows the join code and link, and
/// live participation counts. Links to the question review screen. To do:
/// instructor sign-in, course and question selection, QR code (qr_flutter), live insights from the engine, release
/// feedback.
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  /// Null when the signed-in instructor has no course yet.
  Future<(Course, List<QuestionView>)?>? _content;
  Session? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= _loadContent();
  }

  Future<(Course, List<QuestionView>)?> _loadContent() async {
    final repo = ServicesScope.of(context).content;
    final course = (await repo.listCourses()).firstOrNull;
    if (course == null) return null;
    return (course, await repo.listQuestions(course.id));
  }

  Future<void> _create(Course course, List<QuestionView> questions) async {
    final services = ServicesScope.of(context);
    final session = await services.sessions.createSession(
      courseId: course.id,
      ownerId: services.auth.instructorId!,
      questions: [for (final q in questions) QuestionRef(q.id, q.version)],
    );
    if (!mounted) return;
    setState(() => _session = session);
  }

  /// Review screen; the number of approved questions may change there.
  Future<void> _openReview() async {
    await Navigator.of(context).pushNamed('/instructor/review');
    if (mounted) setState(() => _content = _loadContent());
  }

  String? _joinLink(String code) =>
      kIsWeb ? '${Uri.base.origin}/#/join/$code' : null;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.instructorCreateSessionTitle),
        actions: [
          if (ServicesScope.of(context).auth.requiresSignIn)
            IconButton(
              tooltip: l.authSignOut,
              icon: const Icon(Icons.logout),
              onPressed: () => ServicesScope.of(context).auth.signOut(),
            ),
          const LanguageSwitcher(),
        ],
      ),
      body: FutureBuilder<(Course, List<QuestionView>)?>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(l.errorGeneric));
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data;
          if (data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.instructorNoCourse, textAlign: TextAlign.center),
              ),
            );
          }
          final (course, questions) = data;
          final session = _session;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                course.name.of(currentLanguage(context)),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(l.instructorQuestionsAvailable(questions.length)),
              const SizedBox(height: 24),
              if (session == null) ...[
                OutlinedButton.icon(
                  onPressed: _openReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(l.instructorReviewQuestions),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: questions.isEmpty
                      ? null
                      : () => _create(course, questions),
                  child: Text(l.instructorCreateSession),
                ),
              ] else
                _LiveSessionPanel(
                  session: session,
                  joinLink: _joinLink(session.code),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveSessionPanel extends StatelessWidget {
  const _LiveSessionPanel({required this.session, required this.joinLink});

  final Session session;
  final String? joinLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sessions = ServicesScope.of(context).sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Codes and links are left-to-right even in the Arabic UI.
        Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(
            session.code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        Text(l.instructorJoinCode(session.code), textAlign: TextAlign.center),
        if (joinLink != null)
          SelectableText(
            l.instructorJoinLink(joinLink!),
            textAlign: TextAlign.center,
          ),
        if (joinLink != null) ...[
          const SizedBox(height: 16),
          JoinQr(link: joinLink!, code: session.code),
        ],
        const SizedBox(height: 24),
        StreamBuilder(
          stream: sessions.watchResponses(session.id),
          builder: (context, snapshot) {
            final responses = snapshot.data ?? const [];
            final participants = responses
                .map((r) => r.participantId)
                .toSet()
                .length;
            return Text(
              l.instructorLiveCounts(participants, responses.length),
              textAlign: TextAlign.center,
            );
          },
        ),
        const SizedBox(height: 24),
        StreamBuilder<Session>(
          stream: sessions.watchSession(session.id),
          builder: (context, snapshot) {
            final closed = snapshot.data?.status == SessionStatus.closed;
            return closed
                ? Text(l.instructorSessionClosed, textAlign: TextAlign.center)
                : OutlinedButton(
                    onPressed: () => sessions.closeSession(session.id),
                    child: Text(l.instructorCloseSession),
                  );
          },
        ),
      ],
    );
  }
}
