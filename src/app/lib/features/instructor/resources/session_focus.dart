import 'package:bousla_engine/bousla_engine.dart';

import '../../../app_services.dart';
import '../../../data/models.dart';
import '../sessions/live_insights.dart' show computeClassInsights;

/// The latest session with answers, and what its class results say students
/// may need (for AI resource suggestions when the instructor writes no
/// description).
class SessionFocus {
  const SessionFocus({required this.session, required this.focus});

  final Session session;
  final ClassResourceFocus focus;
}

/// Loads [SessionFocus] for [courseId], or null when there is no session
/// with answers (or anything fails: the suggestions then use the chosen
/// concepts only). Runs the same engine pipeline as the live insights
/// ([computeClassInsights], groups under 3 students hidden) and only reads
/// its aggregate result: no student ID, answer or count reaches the model.
/// Looks at the [maxSessions] newest sessions at most.
Future<SessionFocus?> loadLatestSessionFocus(
  AppServices services,
  String courseId, {
  int maxSessions = 3,
}) async {
  try {
    final owner = services.auth.instructorId;
    if (owner == null) return null;
    final sessions = await services.sessions.listSessions(
      ownerId: owner,
      courseId: courseId,
    );
    for (final session in sessions.take(maxSessions)) {
      final responses =
          await services.sessions.watchResponses(session.id).first;
      if (responses.isEmpty) continue;
      final questions = await services.content.questionsForSession(
        courseId,
        session.questions,
      );
      final insights = computeClassInsights(
        responses: responses,
        questions: [for (final q in questions) q.question],
        keys: await services.content.answerKeys(courseId),
        concepts: await services.content.listConcepts(courseId),
      );
      return SessionFocus(
        session: session,
        focus: classResourceFocus(insights),
      );
    }
    return null;
  } catch (_) {
    return null;
  }
}
