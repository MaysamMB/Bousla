import 'dart:async';
import 'dart:math';

import 'package:bousla_engine/bousla_engine.dart';

import '../join_code.dart';
import '../models.dart';
import '../repositories/session_repository.dart';

/// Development implementation. Everything lives in memory and disappears on
/// restart. Data is not shared between browser tabs or devices: to try the
/// instructor and student flows together before Firebase is connected, use
/// both in the same running app.
class InMemorySessionRepository implements SessionRepository {
  InMemorySessionRepository({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  final _sessions = <String, Session>{};
  final _responses = <String, List<Response>>{};
  final _sessionControllers = <String, StreamController<Session>>{};
  final _responseControllers = <String, StreamController<List<Response>>>{};
  var _nextId = 1;

  Session _require(String sessionId) =>
      _sessions[sessionId] ?? (throw StateError('Unknown session $sessionId'));

  void _update(Session session) {
    _sessions[session.id] = session;
    _sessionControllers[session.id]?.add(session);
  }

  @override
  Future<Session> createSession({
    required String courseId,
    required String ownerId,
    required List<QuestionRef> questions,
  }) async {
    var code = generateJoinCode(_random);
    while (_sessions.values.any((s) => s.code == code)) {
      code = generateJoinCode(_random);
    }
    final session = Session(
      id: 'session_${_nextId++}',
      code: code,
      courseId: courseId,
      ownerId: ownerId,
      questions: List.unmodifiable(questions),
      status: SessionStatus.open,
      feedbackReleased: false,
    );
    _sessions[session.id] = session;
    _responses[session.id] = [];
    return session;
  }

  @override
  Future<Session?> findByCode(String code) async {
    final normalized = normalizeJoinCode(code);
    for (final s in _sessions.values) {
      if (s.code == normalized) return s;
    }
    return null;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    final controller = _sessionControllers.putIfAbsent(
      sessionId,
      () => StreamController<Session>.broadcast(),
    );
    return Stream.multi((listener) {
      listener.add(_require(sessionId));
      final sub = controller.stream.listen(listener.add);
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<String> join(String sessionId) async {
    _require(sessionId);
    // Avoids bit shifts: they are 32-bit on the web.
    return 'participant_${generateJoinCode(_random)}${generateJoinCode(_random)}';
  }

  @override
  Future<void> submitResponse(String sessionId, Response response) async {
    final session = _require(sessionId);
    if (session.status == SessionStatus.closed)
      throw SessionClosedException(sessionId);
    final list = _responses[sessionId]!;
    final duplicate = list.any(
      (r) =>
          r.participantId == response.participantId &&
          r.questionId == response.questionId &&
          r.questionVersion == response.questionVersion,
    );
    if (duplicate) throw DuplicateAnswerException(response.questionId);
    list.add(response);
    _responseControllers[sessionId]?.add(List.unmodifiable(list));
  }

  @override
  Stream<List<Response>> watchResponses(String sessionId) {
    _require(sessionId);
    final controller = _responseControllers.putIfAbsent(
      sessionId,
      () => StreamController<List<Response>>.broadcast(),
    );
    return Stream.multi((listener) {
      listener.add(List.unmodifiable(_responses[sessionId]!));
      final sub = controller.stream.listen(listener.add);
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> closeSession(String sessionId) async =>
      _update(_require(sessionId).copyWith(status: SessionStatus.closed));

  @override
  Future<void> releaseFeedback(String sessionId) async =>
      _update(_require(sessionId).copyWith(feedbackReleased: true));
}
