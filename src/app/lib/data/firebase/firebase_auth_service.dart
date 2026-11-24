import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/auth_service.dart';

/// [AuthService] on Firebase Authentication: email/password for
/// instructors, anonymous sign-in for students.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  static String? _instructorUid(User? user) =>
      user == null || user.isAnonymous ? null : user.uid;

  @override
  bool get requiresSignIn => true;

  @override
  String? get instructorId => _instructorUid(_auth.currentUser);

  @override
  Stream<String?> instructorChanges() =>
      _auth.authStateChanges().map(_instructorUid);

  @override
  Future<void> signInInstructor(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  @override
  Future<void> registerInstructor(String email, String password) => _auth
      .createUserWithEmailAndPassword(email: email.trim(), password: password);

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> ensureParticipant() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return user.uid;
  }
}
