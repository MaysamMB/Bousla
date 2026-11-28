import 'package:bousla_engine/bousla_engine.dart';

import '../feedback.dart';
import '../models.dart';
import '../repositories/follow_up_repository.dart';
import 'in_memory_content_repository.dart';
import 'in_memory_session_repository.dart';

/// Offline demo and tests. Plays the backend: it makes the same checks as
/// `firebase/firestore.rules` (owner, released feedback, eligible concepts,
/// answer once, grade against the answer key) inside the repository, so
/// screens only ever see questions, options and right/wrong results.
class InMemoryFollowUpRepository implements FollowUpRepository {
  InMemoryFollowUpRepository({
    required InMemoryContentRepository content,
    required InMemorySessionRepository sessions,
    required Future<String> Function() currentUser,
  })  : _content = content,
        _sessions = sessions,
        _currentUser = currentUser;

  final InMemoryContentRepository _content;
  final InMemorySessionRepository _sessions;
  final Future<String> Function() _currentUser;

  final _attempts = <String, FollowUpAttempt>{};
  final _answers = <String, Map<QuestionRef, String>>{};
  final _grades = <String, Map<QuestionRef, FollowUpGrade>>{};

  /// Every attempt, as stored (tests: privacy and duplicates).
  Iterable<FollowUpAttempt> get storedAttempts => _attempts.values;

  Future<FollowUpAttempt> _own(FollowUpAttempt attempt) async {
    final uid = await _currentUser();
    final stored = _attempts[attempt.id];
    if (stored == null || stored.ownerId != uid) {
      throw const FollowUpAccessDenied();
    }
    return stored;
  }

  @override
  Future<FollowUpAttempt?> findAttempt(String sessionId) async {
    final uid = await _currentUser();
    return _attempts[FollowUpAttempt.idFor(uid, sessionId)];
  }

  @override
  Future<FollowUpAttempt> startAttempt({
    required Session session,
    required StudentFeedback feedback,
    required List<String> conceptIds,
    required Language language,
  }) async {
    final uid = await _currentUser();
    final id = FollowUpAttempt.idFor(uid, session.id);
    if (_attempts[id] case final existing?) return existing;

    // As the rules do: trust the stored feedback, not the browser's copy.
    final stored = _sessions.releasedFeedback(session.id, uid);
    if (stored == null) {
      throw const FollowUpUnavailable(FollowUpProblem.notOwner);
    }
    final eligible = stored.reviewConceptIds.toSet();
    if (conceptIds.isEmpty || !conceptIds.every(eligible.contains)) {
      throw const FollowUpUnavailable(FollowUpProblem.notEligible);
    }
    final plan = reassessmentFor(stored, conceptIds);
    if (plan.questions.isEmpty) {
      throw const FollowUpUnavailable(FollowUpProblem.noQuestions);
    }
    // Checked again here, as a re-entrant press may have created it.
    return _attempts.putIfAbsent(
      id,
      () => FollowUpAttempt(
        id: id,
        ownerId: uid,
        sessionId: session.id,
        courseId: session.courseId,
        conceptIds: List.unmodifiable(plan.concepts),
        questions: [
          for (final q in plan.questions) QuestionRef(q.questionId, q.version),
        ],
        language: language,
        status: FollowUpStatus.inProgress,
      ),
    );
  }

  @override
  Future<List<QuestionView>> questions(FollowUpAttempt attempt) async {
    final a = await _own(attempt);
    return _content.questionsForSession(a.courseId, a.questions);
  }

  @override
  Future<void> answer(
    FollowUpAttempt attempt,
    QuestionRef question,
    String selectedOptionId,
  ) async {
    final a = await _own(attempt);
    if (!a.questions.contains(question)) throw const FollowUpAccessDenied();
    final answers = _answers.putIfAbsent(a.id, () => {});
    // Once only: a stored answer is never replaced.
    if (!answers.containsKey(question)) {
      if (a.status != FollowUpStatus.inProgress) {
        throw const FollowUpAccessDenied();
      }
      answers[question] = selectedOptionId;
    }
    final grades = _grades.putIfAbsent(a.id, () => {});
    if (grades.containsKey(question)) return;
    final keys = await _content.answerKeys(a.courseId);
    final key = keys.firstWhere((k) =>
        k.questionId == question.questionId &&
        k.questionVersion == question.version);
    final q =
        (await _content.questionsForSession(a.courseId, [question])).single;
    grades[question] = FollowUpGrade(
      conceptIds: q.conceptIds,
      correct: answers[question] == key.correctOptionId,
    );
  }

  @override
  Future<Set<QuestionRef>> graded(FollowUpAttempt attempt) async {
    final a = await _own(attempt);
    return {...?_grades[a.id]?.keys};
  }

  @override
  Future<List<FollowUpGrade>> grades(FollowUpAttempt attempt) async {
    final a = await _own(attempt);
    return [...?_grades[a.id]?.values];
  }

  @override
  Future<FollowUpAttempt> finish(FollowUpAttempt attempt) async {
    final a = await _own(attempt);
    final done = FollowUpAttempt(
      id: a.id,
      ownerId: a.ownerId,
      sessionId: a.sessionId,
      courseId: a.courseId,
      conceptIds: a.conceptIds,
      questions: a.questions,
      language: a.language,
      status: FollowUpStatus.finished,
    );
    _attempts[a.id] = done;
    return done;
  }
}
