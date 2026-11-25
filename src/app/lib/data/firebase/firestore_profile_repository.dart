import 'package:bousla_engine/bousla_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../feedback.dart';
import '../models.dart';
import '../repositories/profile_repository.dart';

/// [ProfileRepository] on Firestore:
///
///   profiles/{uid}                  consent_version, consented_at, created_at
///   profiles/{uid}/sessions/{code}  course_id, title, concepts, added_at
///
/// firebase/firestore.rules lets only the student, with a linked account,
/// read or change these, and only add a session whose feedback was released
/// for them.
class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _db.collection('profiles').doc(uid);

  CollectionReference<Map<String, dynamic>> _sessions(String uid) =>
      _profile(uid).collection('sessions');

  @override
  Future<int?> consentVersion(String uid) async {
    final doc = await _profile(uid).get();
    return doc.data()?['consent_version'] as int?;
  }

  @override
  Future<void> create(String uid, {int consentVersion = profileConsentVersion}) =>
      _profile(uid).set({
        'consent_version': consentVersion,
        'consented_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> saveSession(String uid, Session session, StudentFeedback feedback) =>
      _sessions(uid).doc(session.code).set(
            savedSessionToJson(savedSessionFrom(session, feedback)),
          );

  @override
  Future<List<SavedSession>> sessions(String uid) async {
    final snap = await _sessions(uid).get();
    final list = [for (final d in snap.docs) savedSessionFromJson(d.id, d.data())];
    list.sort((a, b) {
      final at = a.addedAt, bt = b.addedAt;
      if (at == null || bt == null) return at == null ? 1 : -1;
      return at.compareTo(bt);
    });
    return list;
  }

  @override
  Future<bool> hasSession(String uid, String code) async =>
      (await _sessions(uid).doc(code).get()).exists;

  @override
  Future<void> removeSession(String uid, String code) =>
      _sessions(uid).doc(code).delete();

  @override
  Future<void> delete(String uid) async {
    final snap = await _sessions(uid).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_profile(uid));
    await batch.commit();
  }
}

Map<String, dynamic> savedSessionToJson(SavedSession s) => {
      'course_id': s.courseId,
      'title': s.title == null ? null : {'ar': s.title!.ar, 'en': s.title!.en},
      'concepts': [
        for (final c in s.concepts)
          {
            'id': c.conceptId,
            'name': {'ar': c.name.ar, 'en': c.name.en},
            'state': c.state.name,
            'attempts': c.attempts,
            'correct': c.correct,
          },
      ],
      'added_at': FieldValue.serverTimestamp(),
    };

SavedSession savedSessionFromJson(String code, Map<String, dynamic> j) {
  LocalizedText? text(Object? v) => v is Map
      ? LocalizedText(ar: '${v['ar'] ?? ''}', en: '${v['en'] ?? ''}')
      : null;
  return SavedSession(
    code: code,
    courseId: j['course_id'] as String? ?? '',
    title: text(j['title']),
    addedAt: (j['added_at'] as Timestamp?)?.toDate(),
    concepts: [
      for (final c in (j['concepts'] as List? ?? const []))
        if (c is Map)
          SavedConcept(
            conceptId: '${c['id']}',
            name: text(c['name']) ?? LocalizedText(ar: '${c['id']}', en: '${c['id']}'),
            state: MasteryState.values.firstWhere(
              (s) => s.name == c['state'],
              orElse: () => MasteryState.insufficientEvidence,
            ),
            attempts: (c['attempts'] as num?)?.toInt() ?? 0,
            correct: (c['correct'] as num?)?.toInt() ?? 0,
          ),
    ],
  );
}
