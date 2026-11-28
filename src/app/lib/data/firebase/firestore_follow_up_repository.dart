import 'package:bousla_engine/bousla_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../feedback.dart';
import '../models.dart';
import '../repositories/follow_up_repository.dart';
import 'firestore_codec.dart';

/// [FollowUpRepository] on Cloud Firestore, without a server (Spark plan).
/// Layout, all checked by `firebase/firestore.rules`:
///
///   followups/{uid}_{sessionId}        the attempt: owner, original session,
///                                      reviewed concepts, question keys
///                                      (only ones the instructor app
///                                      reserved in this student's feedback)
///     answers/{questionId}_v{n}        the answer, written once
///     grades/{questionId}_v{n}         right or wrong, accepted by the rules
///                                      only when it matches the answer key
///
/// Grading without exposing keys: the browser first stores its answer (it
/// can never change), then writes a grade. The rules compare the stored
/// answer with `answer_keys` on the server and accept only the true value,
/// so the browser learns whether its own locked answer was right, never
/// the key, and cannot store a wrong result. Answer and grade are separate
/// writes on purpose: the rules' `get()` sees only the answer already
/// stored, so trying options in one batch is refused.
///
/// The browser never lists the question bank: it opens only the questions
/// reserved for it, by ID. No instructor can read any of it.
class FirestoreFollowUpRepository implements FollowUpRepository {
  FirestoreFollowUpRepository(
    this._db, {
    required Future<String> Function() ensureParticipant,
  }) : _ensureParticipant = ensureParticipant;

  final FirebaseFirestore _db;
  final Future<String> Function() _ensureParticipant;

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _db.collection('followups');

  DocumentReference<Map<String, dynamic>> _attemptDoc(String id) =>
      _attempts.doc(id);

  static bool _denied(Object e) =>
      e is FirebaseException && e.code == 'permission-denied';

  static FollowUpAttempt _fromDoc(String id, Map<String, dynamic> d) =>
      FollowUpAttempt(
        id: id,
        ownerId: d['owner_id'] as String,
        sessionId: d['session_id'] as String,
        courseId: d['course_id'] as String,
        conceptIds: [for (final c in d['concept_ids'] as List) c as String],
        questions: [
          for (final k in d['question_keys'] as List) _refOf(k as String),
        ],
        language: d['language'] == 'en' ? Language.en : Language.ar,
        status: d['status'] == 'finished'
            ? FollowUpStatus.finished
            : FollowUpStatus.inProgress,
      );

  /// `{questionId}_v{n}` back to a [QuestionRef].
  static QuestionRef _refOf(String key) {
    final i = key.lastIndexOf('_v');
    return QuestionRef(key.substring(0, i), int.parse(key.substring(i + 2)));
  }

  static String _key(QuestionRef q) => questionDocId(q.questionId, q.version);

  @override
  Future<FollowUpAttempt?> findAttempt(String sessionId) async {
    final uid = await _ensureParticipant();
    final id = FollowUpAttempt.idFor(uid, sessionId);
    final snap = await _attemptDoc(id).get();
    final data = snap.data();
    return data == null ? null : _fromDoc(id, data);
  }

  @override
  Future<FollowUpAttempt> startAttempt({
    required Session session,
    required StudentFeedback feedback,
    required List<String> conceptIds,
    required Language language,
  }) async {
    final uid = await _ensureParticipant();
    final id = FollowUpAttempt.idFor(uid, session.id);
    if (await findAttempt(session.id) case final existing?) return existing;

    // The questions the instructor app reserved for this student; the
    // rules refuse any other (and any concept not in the feedback).
    final plan = reassessmentFor(feedback, conceptIds);
    if (plan.questions.isEmpty) {
      throw FollowUpUnavailable(
          conceptIds.any(feedback.reviewConceptIds.contains)
              ? FollowUpProblem.noQuestions
              : FollowUpProblem.notEligible);
    }

    // Its ID is fixed, so two presses make one attempt: the second create
    // is refused (create only) and the first one is read.
    try {
      await _attemptDoc(id).set({
        'owner_id': uid,
        'session_id': session.id,
        'course_id': session.courseId,
        'concept_ids': plan.concepts,
        'question_keys': [for (final q in plan.questions) q.key],
        'language': language.name,
        'status': 'in_progress',
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!_denied(e)) rethrow;
      if (await findAttempt(session.id) case final existing?) return existing;
      // Refused and not there: not this student's feedback or questions.
      throw const FollowUpUnavailable(FollowUpProblem.notOwner);
    }
    return (await findAttempt(session.id))!;
  }

  @override
  Future<List<QuestionView>> questions(FollowUpAttempt attempt) async {
    final items =
        _db.collection('courses').doc(attempt.courseId).collection('questions');
    final docs = await Future.wait([
      for (final q in attempt.questions) items.doc(_key(q)).get(),
    ]);
    return [
      for (final d in docs)
        if (d.data() case final data?) QuestionView.fromJson(data),
    ];
  }

  @override
  Future<void> answer(
    FollowUpAttempt attempt,
    QuestionRef question,
    String selectedOptionId,
  ) async {
    final key = _key(question);
    final doc = _attemptDoc(attempt.id);
    final answerDoc = doc.collection('answers').doc(key);
    final gradeDoc = doc.collection('grades').doc(key);

    // 1. The answer, once. After a lost reply it may already be stored.
    if (!(await answerDoc.get()).exists) {
      try {
        await answerDoc.set({
          'question_id': question.questionId,
          'question_version': question.version,
          'selected_option_id': selectedOptionId,
          'answered_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (!_denied(e) || !(await answerDoc.get()).exists) rethrow;
      }
    }

    // 2. The grade, checked by the rules against the answer key.
    if ((await gradeDoc.get()).exists) return;
    final q = await _db
        .collection('courses')
        .doc(attempt.courseId)
        .collection('questions')
        .doc(key)
        .get();
    final concepts = [
      for (final c in (q.data()?['concept_ids'] as List? ?? const []))
        c as String,
    ];
    for (final correct in [true, false]) {
      try {
        await gradeDoc.set({
          'correct': correct,
          'concept_ids': concepts,
          'graded_at': FieldValue.serverTimestamp(),
        });
        return;
      } catch (e) {
        if (!_denied(e)) rethrow;
        if ((await gradeDoc.get()).exists) return;
      }
    }
    throw const FollowUpAccessDenied();
  }

  @override
  Future<Set<QuestionRef>> graded(FollowUpAttempt attempt) async {
    final snap = await _attemptDoc(attempt.id).collection('grades').get();
    return {for (final d in snap.docs) _refOf(d.id)};
  }

  @override
  Future<List<FollowUpGrade>> grades(FollowUpAttempt attempt) async {
    final snap = await _attemptDoc(attempt.id).collection('grades').get();
    return [
      for (final d in snap.docs)
        FollowUpGrade(
          conceptIds: [
            for (final c in (d.data()['concept_ids'] as List? ?? const []))
              c as String,
          ],
          correct: d.data()['correct'] == true,
        ),
    ];
  }

  @override
  Future<FollowUpAttempt> finish(FollowUpAttempt attempt) async {
    final doc = _attemptDoc(attempt.id);
    if (attempt.status != FollowUpStatus.finished) {
      await doc.update({
        'status': 'finished',
        'finished_at': FieldValue.serverTimestamp(),
      });
    }
    return _fromDoc(attempt.id, (await doc.get()).data()!);
  }
}
