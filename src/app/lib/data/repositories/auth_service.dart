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
  Future<String> ensureParticipant() async => 'participant';
}
