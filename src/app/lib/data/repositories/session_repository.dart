import 'package:bousla_engine/bousla_engine.dart';

import '../models.dart';

/// Sessions, participation and responses.
///
/// Implementations: [InMemorySessionRepository] (development) and a Firestore
/// implementation (owner: backend).
abstract interface class SessionRepository {
  /// Creates an open session with a fresh join code.
  Future<Session> createSession({
    required String courseId,
    required String ownerId,
    required List<QuestionRef> questions,
  });

  /// Finds a session by its join code (case-insensitive). Null if none.
  Future<Session?> findByCode(String code);

  Stream<Session> watchSession(String sessionId);

  /// Registers the current device as a participant and returns its
  /// session-only participant ID (in Firebase: the anonymous auth UID).
  /// This is not a persistent student identity.
  Future<String> join(String sessionId);

  /// Throws [SessionClosedException] if the session is closed and
  /// [DuplicateAnswerException] if this participant already answered this
  /// question version.
  Future<void> submitResponse(String sessionId, Response response);

  /// Instructor only: live stream of all responses in a session.
  Stream<List<Response>> watchResponses(String sessionId);

  Future<void> closeSession(String sessionId);

  Future<void> releaseFeedback(String sessionId);
}
