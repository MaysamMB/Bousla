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

/// How the student shows themselves in their own profile. Seen by them
/// only (the rules give nobody else access); deleted with the profile.
class ProfileInfo {
  const ProfileInfo({this.displayName, this.avatar});

  /// At most [maxNameLength] characters; null when not set.
  final String? displayName;

  /// One of the preset pictures (0 to [avatarCount] - 1); null when not set.
  final int? avatar;

  static const maxNameLength = 40;
  static const avatarCount = 12;
}

/// The optional personal learning profile (architecture §10). Only the
/// student reads or changes it; the security rules allow nobody else,
/// instructors included.
abstract interface class ProfileRepository {
  /// The consent version the student agreed to, or null (no profile).
  Future<int?> consentVersion(String uid);

  /// Records the student's consent and creates the profile.
  Future<void> create(String uid, {int consentVersion = profileConsentVersion});

  /// Adds [session] with the student's own released [feedback]. With
  /// [handoverId], the feedback is this browser's from before it signed in
  /// to an existing profile ([createHandover]).
  Future<void> saveSession(
    String uid,
    Session session,
    StudentFeedback feedback, {
    String? handoverId,
  });

  /// Written by this browser while still anonymous ([fromUid]), before it
  /// signs in to a Google account that already has a profile: lets that
  /// profile add [sessionId] for 10 minutes. Returns the handover's id.
  Future<String> createHandover(String sessionId, String fromUid);

  /// The saved sessions, oldest first.
  Future<List<SavedSession>> sessions(String uid);

  Future<bool> hasSession(String uid, String code);

  Future<void> removeSession(String uid, String code);

  /// Deletes every saved session, then the profile itself.
  Future<void> delete(String uid);

  /// The student's name and picture for their own profile.
  Future<ProfileInfo> info(String uid);

  /// Sets them; an empty name or a null avatar clears that one. The consent
  /// record stays as it was.
  Future<void> updateInfo(String uid, ProfileInfo info);
}

/// Development and tests: in this tab only.
class InMemoryProfileRepository implements ProfileRepository {
  final _consent = <String, int>{};
  final _sessions = <String, Map<String, SavedSession>>{};

  @override
  Future<int?> consentVersion(String uid) async => _consent[uid];

  @override
  Future<void> create(String uid,
      {int consentVersion = profileConsentVersion}) async {
    _consent[uid] = consentVersion;
  }

  /// Handovers written in this tab: id -> session id.
  final handovers = <String, String>{};

  @override
  Future<String> createHandover(String sessionId, String fromUid) async {
    final id = 'handover-${handovers.length + 1}';
    handovers[id] = sessionId;
    return id;
  }

  @override
  Future<void> saveSession(
    String uid,
    Session session,
    StudentFeedback feedback, {
    String? handoverId,
  }) async {
    if (!_consent.containsKey(uid)) throw StateError('no profile');
    if (handoverId != null && handovers[handoverId] != session.id) {
      throw StateError('no handover for this session');
    }
    (_sessions[uid] ??= {})[session.id] =
        savedSessionFrom(session, feedback, addedAt: DateTime.now());
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
    _info.remove(uid);
  }

  final _info = <String, ProfileInfo>{};

  @override
  Future<ProfileInfo> info(String uid) async =>
      _info[uid] ?? const ProfileInfo();

  @override
  Future<void> updateInfo(String uid, ProfileInfo info) async {
    if (!_consent.containsKey(uid)) throw StateError('no profile');
    _info[uid] = cleanProfileInfo(info);
  }
}

/// [info] as stored: the name trimmed and cut to its maximum length (empty
/// becomes null), an avatar outside the presets dropped.
ProfileInfo cleanProfileInfo(ProfileInfo info) {
  var name = info.displayName?.trim() ?? '';
  if (name.length > ProfileInfo.maxNameLength) {
    name = name.substring(0, ProfileInfo.maxNameLength).trim();
  }
  final a = info.avatar;
  return ProfileInfo(
    displayName: name.isEmpty ? null : name,
    avatar: a != null && a >= 0 && a < ProfileInfo.avatarCount ? a : null,
  );
}

SavedSession savedSessionFrom(
  Session session,
  StudentFeedback feedback, {
  DateTime? addedAt,
}) =>
    SavedSession(
      // The session's document ID (the join code on Firestore), as in
      // profiles/{uid}/sessions/{id} and the security rules.
      code: session.id,
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
