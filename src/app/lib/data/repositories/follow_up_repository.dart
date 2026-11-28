import 'package:bousla_engine/bousla_engine.dart';

import '../feedback.dart';
import '../models.dart';

/// "Test my understanding again": a private follow-up for one student on
/// concepts from one session's feedback. No instructor creates, sees or
/// grades it. One attempt per student and original session (its ID is
/// derived from both), so a repeated press or a retry resumes it instead of
/// creating another.
///
/// Implementations: [InMemoryFollowUpRepository] (offline demo, tests) and
/// [FirestoreFollowUpRepository], where `firebase/firestore.rules` checks
/// ownership, eligibility and every grade against the answer key on the
/// server; the browser never reads an answer key.
abstract interface class FollowUpRepository {
  /// The current student's attempt for [sessionId], or null. Only that
  /// student can read it.
  Future<FollowUpAttempt?> findAttempt(String sessionId);

  /// Returns the current student's attempt for [session], creating it on
  /// the first call from the questions reserved in [feedback] (the
  /// student's own released feedback) for [conceptIds]: new questions
  /// chosen by the instructor app at publish time, never ones asked in the
  /// session. The browser never lists the question bank. The backend checks
  /// that the concepts and questions are the ones reserved for this
  /// student.
  ///
  /// Throws [FollowUpUnavailable] when no attempt can be made.
  Future<FollowUpAttempt> startAttempt({
    required Session session,
    required StudentFeedback feedback,
    required List<String> conceptIds,
    required Language language,
  });

  /// The attempt's questions (prompts and options only, never a key).
  Future<List<QuestionView>> questions(FollowUpAttempt attempt);

  /// Saves the answer to [question] (once; it cannot be changed) and then
  /// has it graded by the backend. Safe to call again after a network
  /// error: an answer or grade already stored is kept as it is.
  Future<void> answer(
    FollowUpAttempt attempt,
    QuestionRef question,
    String selectedOptionId,
  );

  /// The question versions already answered and graded, to resume.
  Future<Set<QuestionRef>> graded(FollowUpAttempt attempt);

  /// The graded answers (correct or not, and the question's concepts).
  Future<List<FollowUpGrade>> grades(FollowUpAttempt attempt);

  /// Marks the attempt finished: no more answers.
  Future<FollowUpAttempt> finish(FollowUpAttempt attempt);
}

enum FollowUpStatus { inProgress, finished }

/// The concepts and reserved questions an attempt on [conceptIds] uses: the
/// ticked concepts that may need review or are still forming and have
/// reserved questions, at most [maxFollowUpConcepts], with their reserved
/// questions (at most [followUpQuestionsPerConcept] each).
({List<String> concepts, List<ReassessmentQuestion> questions}) reassessmentFor(
    StudentFeedback feedback, List<String> conceptIds) {
  final eligible = feedback.reviewConceptIds.toSet();
  final concepts = <String>[];
  final questions = <ReassessmentQuestion>[];
  for (final id in conceptIds.toSet()) {
    if (!eligible.contains(id)) continue;
    final mine = [
      for (final q in feedback.reassessment)
        if (q.conceptId == id) q,
    ].take(followUpQuestionsPerConcept);
    if (mine.isEmpty) continue;
    if (concepts.length >= maxFollowUpConcepts) break;
    concepts.add(id);
    questions.addAll(mine);
  }
  return (concepts: concepts, questions: questions);
}

/// Why a follow-up cannot be made.
enum FollowUpProblem {
  /// None of the concepts may be tested: not "may need review" or "still
  /// forming" in the released feedback.
  notEligible,

  /// No new question was reserved for these concepts (none left that the
  /// session did not ask, or feedback published before this feature).
  noQuestions,

  /// The student is not the one the feedback belongs to (e.g. signed in to
  /// another account in this browser).
  notOwner,
}

/// Not this student's attempt, or not allowed in its current state.
class FollowUpAccessDenied implements Exception {
  const FollowUpAccessDenied();
}

class FollowUpUnavailable implements Exception {
  const FollowUpUnavailable(this.problem);

  final FollowUpProblem problem;

  @override
  String toString() => 'FollowUpUnavailable($problem)';
}

class FollowUpAttempt {
  const FollowUpAttempt({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.courseId,
    required this.conceptIds,
    required this.questions,
    required this.language,
    required this.status,
  });

  /// `{ownerId}_{sessionId}`.
  final String id;

  /// The student (anonymous or linked UID) who owns it.
  final String ownerId;

  /// The original session whose feedback it follows.
  final String sessionId;
  final String courseId;

  /// The reviewed concepts it tests.
  final List<String> conceptIds;
  final List<QuestionRef> questions;
  final Language language;
  final FollowUpStatus status;

  static String idFor(String ownerId, String sessionId) =>
      '${ownerId}_$sessionId';
}
