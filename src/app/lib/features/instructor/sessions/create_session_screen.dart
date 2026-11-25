import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../course_picker.dart';
import 'join_qr.dart';
import '../../../data/session_title.dart';
import 'live_insights_panel.dart';
import 'past_sessions_screen.dart';
import 'publish_feedback_dialog.dart';

/// All courses, the chosen one, and its approved questions.
typedef _Content = (List<Course>, Course, List<QuestionView>);

/// Skeleton for the instructor flow (owner: instructor app).
///
/// Already works with the in-memory repositories: creates a session from all
/// approved questions of the chosen course (see course_picker.dart), shows the join code and link, and
/// live participation counts. Links to the question review screen. To do:
/// instructor sign-in, course and question selection, QR code (qr_flutter), live insights from the engine. Publishing
/// feedback after closing: [showPublishFeedbackDialog].
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  /// Null when the signed-in instructor has no course yet.
  Future<_Content?>? _content;
  Session? _session;

  /// A session of this course that is still open (e.g. after a reload).
  /// Offered, not opened: the instructor chooses to continue or close it.
  Session? _openFound;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= _loadContent();
  }

  Future<_Content?> _loadContent() async {
    final services = ServicesScope.of(context);
    final repo = services.content;
    final courses = await repo.listCourses();
    final course = chooseCourse(courses, services.selectedCourseId.value);
    if (course == null) return null;
    // A session that is still running (after a reload, or left open) is
    // offered at the top; it is not opened by itself, so "new session"
    // stays a new session.
    final owner = services.auth.instructorId;
    _openFound = null;
    if (_session == null && owner != null) {
      try {
        _openFound = await services.sessions.latestOpenSession(
          ownerId: owner,
          courseId: course.id,
        );
      } catch (e) {
        debugPrint('Bousla: could not look for an open session: $e');
      }
    }
    return (courses, course, await repo.listQuestions(course.id));
  }

  void _continue(Session open) => setState(() {
    _session = open;
    _openFound = null;
  });

  Future<void> _closeFound(Session open) async {
    await ServicesScope.of(context).sessions.closeSession(open.id);
    if (mounted) _reload();
  }

  /// After a session is closed: back to "create" for a new one.
  void _startNew() => setState(() {
    _session = null;
    _content = _loadContent();
  });

  /// Before creating: offer to review, edit or add questions first (the
  /// session uses the approved questions as they are at this moment).
  Future<void> _confirmCreate(
    Course course,
    List<QuestionView> questions,
  ) async {
    final l = AppLocalizations.of(context);
    final choice = await showDialog<_BeforeCreate>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.instructorBeforeCreateTitle),
        content: Text(l.instructorBeforeCreateBody(questions.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.reviewCancel),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_BeforeCreate.review),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l.instructorReviewQuestions),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_BeforeCreate.create),
            child: Text(l.instructorCreateNow),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _BeforeCreate.review:
        await _openReview();
      case _BeforeCreate.create:
        await _create(course, questions);
      case null:
        break;
    }
  }

  Future<void> _create(Course course, List<QuestionView> questions) async {
    final services = ServicesScope.of(context);
    // Named after its concepts, for the past sessions list.
    final concepts = await services.content.listConcepts(course.id);
    final session = await services.sessions.createSession(
      courseId: course.id,
      ownerId: services.auth.instructorId!,
      questions: [for (final q in questions) QuestionRef(q.id, q.version)],
      title: sessionTitleFor(questions, concepts),
    );
    if (!mounted) return;
    setState(() => _session = session);
  }

  // A block body: setState must not get a Future back.
  void _reload() => setState(() {
    _content = _loadContent();
  });

  /// Review screen; the number of approved questions may change there.
  Future<void> _openReview() async {
    await Navigator.of(context).pushNamed('/instructor/review');
    if (mounted) _reload();
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
          IconButton(
            tooltip: l.instructorPastSessions,
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PastSessionsScreen(),
              ),
            ),
          ),
          if (ServicesScope.of(context).auth.requiresSignIn)
            IconButton(
              tooltip: l.authSignOut,
              icon: const Icon(Icons.logout),
              onPressed: () => ServicesScope.of(context).auth.signOut(),
            ),
          const LanguageSwitcher(),
        ],
      ),
      body: FutureBuilder<_Content?>(
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
          final (courses, course, questions) = data;
          final session = _session;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              CoursePicker(
                courses: courses,
                current: course,
                // One session belongs to one course.
                enabled: session == null,
                onChanged: _reload,
              ),
              const SizedBox(height: 8),
              Text(l.instructorQuestionsAvailable(questions.length)),
              const SizedBox(height: 24),
              if (session == null) ...[
                if (_openFound case final open?) ...[
                  _OpenSessionCard(
                    session: open,
                    onContinue: () => _continue(open),
                    onClose: () => _closeFound(open),
                  ),
                  const SizedBox(height: 24),
                ],
                OutlinedButton.icon(
                  onPressed: _openReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(l.instructorReviewQuestions),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/instructor/resources'),
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(l.instructorResTitle),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: questions.isEmpty
                      ? null
                      : () => _confirmCreate(course, questions),
                  child: Text(l.instructorCreateSession),
                ),
              ] else
                _LiveSessionPanel(
                  session: session,
                  joinLink: _joinLink(session.code),
                  onNewSession: _startNew,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveSessionPanel extends StatelessWidget {
  const _LiveSessionPanel({
    required this.session,
    required this.joinLink,
    required this.onNewSession,
  });

  final Session session;
  final String? joinLink;

  /// Shown once the session is closed.
  final VoidCallback onNewSession;

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
        // What the class understands, per concept (Yasmeen's panel).
        const SizedBox(height: 24),
        LiveInsightsPanel(session: session),
        const SizedBox(height: 24),
        StreamBuilder<Session>(
          stream: sessions.watchSession(session.id),
          builder: (context, snapshot) {
            final current = snapshot.data ?? session;
            if (current.status != SessionStatus.closed) {
              return OutlinedButton(
                onPressed: () => sessions.closeSession(session.id),
                child: Text(l.instructorCloseSession),
              );
            }
            // Feedback is published after closing, once (the button goes
            // away when the session says it is released).
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.instructorSessionClosed, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (current.feedbackReleased)
                  Text(
                    l.instructorFeedbackPublished,
                    textAlign: TextAlign.center,
                  )
                else
                  FilledButton.icon(
                    onPressed: () =>
                        showPublishFeedbackDialog(context, current),
                    icon: const Icon(Icons.send_outlined),
                    label: Text(l.instructorPublishFeedback),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onNewSession,
                  icon: const Icon(Icons.add),
                  label: Text(l.instructorStartAnother),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// "You have a session that is still open": continue it or close it.
class _OpenSessionCard extends StatelessWidget {
  const _OpenSessionCard({
    required this.session,
    required this.onContinue,
    required this.onClose,
  });

  final Session session;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.instructorOpenSessionFound, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(sessionTitleText(context, session)),
            Text(
              [
                sessionWhen(context, session.createdAt),
                l.instructorJoinCode('\u2066${session.code}\u2069'),
              ].where((t) => t.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.instructorContinueSession),
                ),
                OutlinedButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l.instructorCloseSession),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _BeforeCreate { review, create }
