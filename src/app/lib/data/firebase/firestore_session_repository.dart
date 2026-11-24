import 'dart:math';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../feedback.dart';
import '../join_code.dart';
import '../models.dart';
import '../repositories/session_repository.dart';
import 'firestore_codec.dart';

/// [SessionRepository] on Cloud Firestore. Layout (docs/architecture.md §6):
///
///   sessions/{CODE}                          the document ID is the join code
///   sessions/{CODE}/participants/{uid}
///   sessions/{CODE}/responses/{uid}_{questionId}_v{n}
///
/// Using the join code as the ID lets a student open a session with a single
/// read, while the security rules refuse listing sessions (no guessing).
/// The rules also refuse answers after closing and second answers; the
/// checks here only turn those cases into the exceptions screens expect.
class FirestoreSessionRepository implements SessionRepository {
  FirestoreSessionRepository(
    this._db, {
    required this.ensureParticipant,
    Random? random,
  }) : _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final Random _random;

  /// Signs the student in (anonymously) if needed and returns their UID.
  final Future<String> Function() ensureParticipant;

  static final _validCode = RegExp(r'^[A-Z0-9]{1,20}$');

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');

  @override
  Future<Session> createSession({
    required String courseId,
    required String ownerId,
    required List<QuestionRef> questions,
  }) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = generateJoinCode(_random);
      final created = Session(
        id: code,
        code: code,
        courseId: courseId,
        ownerId: ownerId,
        questions: List.unmodifiable(questions),
        status: SessionStatus.open,
        feedbackReleased: false,
      );
      final ref = _sessions.doc(created.id);
      final taken = await _db.runTransaction((tx) async {
        if ((await tx.get(ref)).exists) return true;
        tx.set(ref, {
          ...sessionToJson(created),
          'created_at': FieldValue.serverTimestamp(),
        });
        return false;
      });
      if (!taken) return created;
    }
    throw StateError('Could not find a free join code');
  }

  @override
  Future<Session?> latestOpenSession({
    required String ownerId,
    required String courseId,
  }) async {
    // Equality filters only (no index needed); the rules allow listing
    // because the query is limited to the instructor's own sessions.
    final snap = await _sessions
        .where('owner_id', isEqualTo: ownerId)
        .where('course_id', isEqualTo: courseId)
        .where('status', isEqualTo: 'open')
        .get();
    if (snap.docs.isEmpty) return null;
    DateTime created(Map<String, dynamic> d) => d['created_at'] is Timestamp
        ? (d['created_at'] as Timestamp).toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
    var newest = snap.docs.first;
    for (final d in snap.docs.skip(1)) {
      if (created(d.data()).isAfter(created(newest.data()))) newest = d;
    }
    return sessionFromDoc(newest.id, newest.data());
  }

  @override
  Future<Session?> findByCode(String code) async {
    final normalized = normalizeJoinCode(code);
    if (!_validCode.hasMatch(normalized)) return null;
    // The rules only let signed-in users read sessions, so a student coming
    // from a link or QR code is signed in (anonymously) first.
    await ensureParticipant();
    final doc = await _sessions.doc(normalized).get();
    return doc.exists ? sessionFromDoc(doc.id, doc.data()!) : null;
  }

  @override
  Stream<Session> watchSession(String sessionId) => _sessions
      .doc(sessionId)
      .snapshots()
      .where((d) => d.exists)
      .map((d) => sessionFromDoc(d.id, d.data()!));

  @override
  Future<String> join(String sessionId) async {
    final uid = await ensureParticipant();
    final ref = _sessions.doc(sessionId).collection('participants').doc(uid);
    // Joining twice (e.g. reopening the link) is fine; the rules allow
    // creating the document once only.
    if (!(await ref.get()).exists) {
      await ref.set({'joined_at': FieldValue.serverTimestamp()});
    }
    return uid;
  }

  @override
  Future<void> submitResponse(String sessionId, Response response) async {
    final sessionRef = _sessions.doc(sessionId);
    final ref = sessionRef.collection('responses').doc(
          responseDocId(
            response.participantId,
            response.questionId,
            response.questionVersion,
          ),
        );
    Future<void> explainRefusal() async {
      // Both reads at once: one round trip instead of two.
      final checks = await Future.wait([sessionRef.get(), ref.get()]);
      if (checks[0].data()?['status'] == 'closed') {
        throw SessionClosedException(sessionId);
      }
      if (checks[1].exists) {
        throw DuplicateAnswerException(response.questionId);
      }
    }

    await explainRefusal();
    try {
      await ref.set(responseToJson(response));
    } on FirebaseException catch (e) {
      // Closed or answered in the meantime: the rules refused the write.
      if (e.code == 'permission-denied') await explainRefusal();
      rethrow;
    }
  }

  @override
  Future<Set<QuestionRef>> answeredQuestions(
    Session session,
    String participantId,
  ) async {
    // Students may read their own answers one by one (not list them).
    final responses = _sessions.doc(session.id).collection('responses');
    final docs = await Future.wait([
      for (final q in session.questions)
        responses
            .doc(responseDocId(participantId, q.questionId, q.version))
            .get(),
    ]);
    return {
      for (var i = 0; i < docs.length; i++)
        if (docs[i].exists) session.questions[i],
    };
  }

  @override
  Stream<List<Response>> watchResponses(String sessionId) =>
      _sessions.doc(sessionId).collection('responses').snapshots().map(
            (snap) => List.unmodifiable([
              for (final d in snap.docs) responseFromJson(d.data()),
            ]),
          );

  @override
  Future<void> closeSession(String sessionId) => _sessions
      .doc(sessionId)
      .update({'status': 'closed', 'closed_at': FieldValue.serverTimestamp()});

  @override
  Future<void> releaseFeedback(String sessionId) =>
      _sessions.doc(sessionId).update({'feedback_released': true});

  @override
  Future<void> saveFeedback(
    String sessionId,
    Map<String, StudentFeedback> byParticipant,
  ) async {
    final feedback = _sessions.doc(sessionId).collection('feedback');
    final entries = byParticipant.entries.toList();
    // Firestore allows at most 500 writes in one batch.
    for (var i = 0; i < entries.length; i += 450) {
      final batch = _db.batch();
      for (final e in entries.skip(i).take(450)) {
        batch.set(feedback.doc(e.key), {
          ...e.value.toJson(),
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  @override
  Stream<StudentFeedback?> watchMyFeedback(
    String sessionId,
    String participantId,
  ) {
    final doc = _sessions
        .doc(sessionId)
        .collection('feedback')
        .doc(participantId);
    // The rules refuse reading feedback before it is released, so the
    // document is only watched once the session says it is.
    return watchSession(sessionId)
        .map((s) => s.feedbackReleased)
        .distinct()
        .asyncExpand(
          (released) => released
              ? doc.snapshots().map(
                    (d) => d.exists ? StudentFeedback.fromJson(d.data()!) : null,
                  )
              : Stream<StudentFeedback?>.value(null),
        );
  }
}
