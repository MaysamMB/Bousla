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
}

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
