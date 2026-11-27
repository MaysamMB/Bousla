/// Who is using the app.
///
/// - Instructors sign in with email and password; their UID is the
///   `owner_id` of their courses and sessions.
/// - Students never create an account: [ensureParticipant] signs them in
///   anonymously. That UID identifies a participant within a session only,
///   is tied to the browser, and is not a persistent student identity
///   (docs/architecture.md §10).
///
/// Implementations: [InMemoryAuthService] (development, a fixed instructor)
/// and `FirebaseAuthService`.
abstract interface class AuthService {
  /// False in development: there is always a signed-in instructor.
  bool get requiresSignIn;

  /// UID of the signed-in instructor, or null (not signed in, or signed in
  /// anonymously as a student).
  String? get instructorId;

  /// Emits [instructorId] now and whenever it changes.
  Stream<String?> instructorChanges();

  Future<void> signInInstructor(String email, String password);

  Future<void> registerInstructor(String email, String password);

  Future<void> signOut();

  /// Whether the signed-in instructor is in the approved list
  /// (`instructors/{uid}`, edited in the Firebase console). Anyone can
  /// create an account; only approved accounts can own courses and
  /// sessions, and the security rules enforce it. False when not signed in.
  Future<bool> isApprovedInstructor();

  /// The current user's UID, signing in anonymously first if needed.
  Future<String> ensureParticipant();

  /// The student's own account, once they linked one for the optional
  /// personal profile (architecture §10); null while anonymous.
  StudentAccount? get studentAccount;

  /// Links the current anonymous student to a Google account, keeping the
  /// same UID, so the sessions answered in this browser can go into their
  /// own profile. Throws [StudentLinkFailure].
  Future<StudentAccount> linkStudentAccount();

  /// After [StudentLinkProblem.accountInUse]: signs in to that Google
  /// account, which already has a profile from another browser. This
  /// browser then uses that account (its anonymous UID is left behind), so
  /// write a profile handover first. Throws [StudentLinkFailure].
  Future<StudentAccount> switchToLinkedStudentAccount();
}

/// A student's linked account. [label] is what to show them (their email).
class StudentAccount {
  const StudentAccount({required this.uid, required this.label});

  final String uid;
  final String label;
}

enum StudentLinkProblem {
  /// The sign-in window was closed.
  cancelled,

  /// The browser blocked the sign-in window (Safari does when it does not
  /// open straight from a tap): ask the student to tap once more.
  popupBlocked,

  /// This Google account is already linked to another Bousla profile (from
  /// another browser): sign in to it with
  /// [AuthService.switchToLinkedStudentAccount] and hand the session over.
  accountInUse,

  /// Google sign-in is not enabled in the Firebase console.
  notEnabled,
  network,

  /// Nothing to link: the student has not answered in this browser.
  noSession,

  /// This browser is signed in to an instructor account (email and
  /// password), so there is no anonymous student to link: the student must
  /// sign out of the dashboard or use a private window.
  instructorSignedIn,
  unknown,
}

class StudentLinkFailure implements Exception {
  const StudentLinkFailure(this.problem, [this.detail]);

  final StudentLinkProblem problem;
  final String? detail;

  @override
  String toString() => 'StudentLinkFailure($problem, $detail)';
}

StudentLinkProblem studentLinkProblemFromCode(String code) => switch (code) {
      'popup-closed-by-user' ||
      'cancelled-popup-request' ||
      'user-cancelled' =>
        StudentLinkProblem.cancelled,
      'credential-already-in-use' ||
      'provider-already-linked' ||
      'email-already-in-use' ||
      'account-exists-with-different-credential' =>
        StudentLinkProblem.accountInUse,
      'popup-blocked' => StudentLinkProblem.popupBlocked,
      'operation-not-allowed' => StudentLinkProblem.notEnabled,
      'network-request-failed' => StudentLinkProblem.network,
      _ => StudentLinkProblem.unknown,
    };

/// Development implementation: a fixed instructor, no network.
class InMemoryAuthService implements AuthService {
  static const devInstructorId = 'dev-instructor';

  @override
  bool get requiresSignIn => false;

  @override
  String? get instructorId => devInstructorId;

  @override
  Stream<String?> instructorChanges() => Stream.value(devInstructorId);

  @override
  Future<void> signInInstructor(String email, String password) async {}

  @override
  Future<void> registerInstructor(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isApprovedInstructor() async => true;

  @override
  Future<String> ensureParticipant() async => 'participant';

  /// Linked in this tab (development and tests).
  StudentAccount? _student;

  @override
  StudentAccount? get studentAccount => _student;

  /// Tests: the Google account already has a profile under this UID (from
  /// "another browser"), so linking fails with
  /// [StudentLinkProblem.accountInUse].
  String? existingStudentUid;

  @override
  Future<StudentAccount> linkStudentAccount() async {
    if (existingStudentUid != null) {
      throw const StudentLinkFailure(StudentLinkProblem.accountInUse);
    }
    return _student = const StudentAccount(
      uid: 'participant',
      label: 'student@example.com',
    );
  }

  @override
  Future<StudentAccount> switchToLinkedStudentAccount() async =>
      _student = StudentAccount(
        uid: existingStudentUid ?? 'participant',
        label: 'student@example.com',
      );
}

/// Why an instructor could not sign in or create an account.
enum AuthProblem {
  /// Wrong password, or no account with this email. Firebase does not say
  /// which (email enumeration protection), so the message covers both.
  wrongCredentials,
  emailInUse,
  weakPassword,
  invalidEmail,
  network,
  tooManyAttempts,

  /// Email/password sign-in is not enabled in the Firebase console.
  notEnabled,
  unknown,
}

/// Thrown by [AuthService.signInInstructor] and
/// [AuthService.registerInstructor].
class AuthFailure implements Exception {
  const AuthFailure(this.problem, [this.code]);

  final AuthProblem problem;

  /// The original error code, shown for [AuthProblem.unknown] so a new kind
  /// of failure can still be diagnosed.
  final String? code;

  @override
  String toString() => 'AuthFailure($problem, $code)';
}

/// Maps a Firebase Auth error code to an [AuthProblem].
AuthProblem authProblemFromCode(String code) => switch (code) {
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        AuthProblem.wrongCredentials,
      'email-already-in-use' => AuthProblem.emailInUse,
      'weak-password' => AuthProblem.weakPassword,
      'invalid-email' || 'missing-email' => AuthProblem.invalidEmail,
      'network-request-failed' => AuthProblem.network,
      'too-many-requests' => AuthProblem.tooManyAttempts,
      'operation-not-allowed' => AuthProblem.notEnabled,
      _ => AuthProblem.unknown,
    };
