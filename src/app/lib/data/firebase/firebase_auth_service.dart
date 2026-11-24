import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/auth_service.dart';

/// [AuthService] on Firebase Authentication: email/password for
/// instructors, anonymous sign-in for students.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  static String? _instructorUid(User? user) =>
      user == null || user.isAnonymous ? null : user.uid;

  @override
  bool get requiresSignIn => true;

  @override
  String? get instructorId => _instructorUid(_auth.currentUser);

  @override
  Stream<String?> instructorChanges() =>
      _auth.authStateChanges().map(_instructorUid);

  /// Turns Firebase errors into [AuthFailure]s the UI can explain.
  static Future<void> _explain(Future<Object?> Function() call) async {
    try {
      await call();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(authProblemFromCode(e.code), e.code);
    }
  }

  @override
  Future<void> signInInstructor(String email, String password) => _explain(
        () => _auth.signInWithEmailAndPassword(
            email: email.trim(), password: password),
      );

  @override
  Future<void> registerInstructor(String email, String password) => _explain(
        () => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<bool> isApprovedInstructor() async {
    final uid = instructorId;
    if (uid == null) return false;
    // The rules let a user read only their own entry. Read from the server:
    // a cached "missing" must not hide a fresh approval.
    final doc = await _db
        .collection('instructors')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }

  @override
  Future<String> ensureParticipant() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return user.uid;
  }
}
