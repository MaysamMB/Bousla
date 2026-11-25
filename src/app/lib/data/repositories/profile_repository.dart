import 'package:bousla_engine/bousla_engine.dart';

import '../feedback.dart';
import '../models.dart';

/// The version of the consent text the student agreed to (see the
/// `studentProfileConsent…` texts). Raise it when the text changes, so the
/// student is asked again.
const profileConsentVersion = 1;

/// One concept as saved in the profile: name, state and its evidence.
class SavedConcept {
  const SavedConcept({
    required this.conceptId,
    required this.name,
    required this.state,
    required this.attempts,
    required this.correct,
  });

  final String conceptId;
  final LocalizedText name;
  final MasteryState state;
  final int attempts;
  final int correct;
}

/// A session the student added to their profile, copied from their own
/// released feedback.
class SavedSession {
  const SavedSession({
    required this.code,
    required this.courseId,
    required this.concepts,
    this.title,
    this.addedAt,
  });

  final String code;
  final String courseId;
  final LocalizedText? title;
  final List<SavedConcept> concepts;
  final DateTime? addedAt;
}

/// The optional personal learning profile (architecture §10). Only the
/// student reads or changes it; the security rules allow nobody else,
/// instructors included.
abstract interface class ProfileRepository {
  /// The consent version the student agreed to, or null (no profile).
  Future<int?> consentVersion(String uid);

  /// Records the student's consent and creates the profile.
  Future<void> create(String uid, {int consentVersion = profileConsentVersion});

  /// Adds [session] with the student's own released [feedback].
  Future<void> saveSession(String uid, Session session, StudentFeedback feedback);

  /// The saved sessions, oldest first.
  Future<List<SavedSession>> sessions(String uid);

  Future<bool> hasSession(String uid, String code);

  Future<void> removeSession(String uid, String code);

  /// Deletes every saved session, then the profile itself.
  Future<void> delete(String uid);
}

/// Development and tests: in this tab only.
class InMemoryProfileRepository implements ProfileRepository {
  final _consent = <String, int>{};
  final _sessions = <String, Map<String, SavedSession>>{};

  @override
  Future<int?> consentVersion(String uid) async => _consent[uid];

  @override
  Future<void> create(String uid, {int consentVersion = profileConsentVersion}) async {
    _consent[uid] = consentVersion;
  }

  @override
  Future<void> saveSession(String uid, Session session, StudentFeedback feedback) async {
    if (!_consent.containsKey(uid)) throw StateError('no profile');
    (_sessions[uid] ??= {})[session.code] = savedSessionFrom(session, feedback,
        addedAt: DateTime.now());
  }

  @override
  Future<List<SavedSession>> sessions(String uid) async => [
        ...?_sessions[uid]?.values,
      ];

  @override
  Future<bool> hasSession(String uid, String code) async =>
      _sessions[uid]?.containsKey(code) ?? false;

  @override
  Future<void> removeSession(String uid, String code) async {
    _sessions[uid]?.remove(code);
  }

  @override
  Future<void> delete(String uid) async {
    _sessions.remove(uid);
    _consent.remove(uid);
  }
}

SavedSession savedSessionFrom(
  Session session,
  StudentFeedback feedback, {
  DateTime? addedAt,
}) =>
    SavedSession(
      code: session.code,
      courseId: session.courseId,
      title: session.title,
      addedAt: addedAt,
      concepts: [
        for (final FeedbackConcept c in feedback.concepts)
          SavedConcept(
            conceptId: c.conceptId,
            name: c.name,
            state: c.state,
            attempts: c.attempts,
            correct: c.correct,
          ),
      ],
    );
