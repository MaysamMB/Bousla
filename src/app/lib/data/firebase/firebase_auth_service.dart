import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/auth_service.dart';

/// [AuthService] on Firebase Authentication: email/password for
/// instructors, anonymous sign-in for students.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  // Instructors sign in with email and password. A student who linked a
  // Google account for their profile is not an instructor candidate.
  static String? _instructorUid(User? user) =>
      user == null ||
              user.isAnonymous ||
              !user.providerData.any((p) => p.providerId == 'password')
          ? null
          : user.uid;

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
  StudentAccount? get studentAccount {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    if (!user.providerData.any((p) => p.providerId == 'google.com')) {
      return null;
    }
    return StudentAccount(uid: user.uid, label: user.email ?? '');
  }

  @override
  Future<StudentAccount> linkStudentAccount() async {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw const StudentLinkFailure(StudentLinkProblem.noSession);
    }
    try {
      // A Google window; the UID stays the same, so this browser's answers
      // and feedback stay this student's.
      await user.linkWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      // Already linked elsewhere: keep Google's answer, so switching to
      // that account needs no second window.
      _pendingGoogle = e.credential;
      throw StudentLinkFailure(studentLinkProblemFromCode(e.code), e.code);
    }
    return studentAccount ??
        (throw const StudentLinkFailure(StudentLinkProblem.unknown));
  }

  AuthCredential? _pendingGoogle;

  @override
  Future<StudentAccount> switchToLinkedStudentAccount() async {
    final pending = _pendingGoogle;
    _pendingGoogle = null;
    try {
      if (pending != null) {
        try {
          await _auth.signInWithCredential(pending);
        } on FirebaseAuthException {
          // Expired or not reusable: ask Google again.
          await _auth.signInWithPopup(GoogleAuthProvider());
        }
      } else {
        await _auth.signInWithPopup(GoogleAuthProvider());
      }
    } on FirebaseAuthException catch (e) {
      throw StudentLinkFailure(studentLinkProblemFromCode(e.code), e.code);
    }
    return studentAccount ??
        (throw const StudentLinkFailure(StudentLinkProblem.unknown));
  }

  @override
  Future<String> ensureParticipant() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return user.uid;
  }
}
