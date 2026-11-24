/// Firebase settings, passed at build time so no project settings are
/// committed:
///
///   flutter run -d chrome --dart-define-from-file=firebase.env.json
///
/// Copy `firebase.env.example.json` to `firebase.env.json` (git-ignored) and
/// fill it from Firebase console → Project settings → Your apps → Web app.
/// These web settings identify the project; they are not secrets. Access is
/// controlled by Firebase Auth and `firebase/firestore.rules`.
///
/// Without a project ID the app runs on the in-memory repositories.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.authDomain,
    required this.useEmulator,
    required this.emulatorHost,
    this.appCheckSiteKey = '',
  });

  factory FirebaseConfig.fromEnvironment() => const FirebaseConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId:
            String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        useEmulator: bool.fromEnvironment('USE_FIREBASE_EMULATOR'),
        emulatorHost: String.fromEnvironment(
          'FIREBASE_EMULATOR_HOST',
          defaultValue: 'localhost',
        ),
        appCheckSiteKey: String.fromEnvironment('FIREBASE_APPCHECK_SITE_KEY'),
      );

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String authDomain;

  /// Connect to the local emulators (`firebase emulators:start`) instead of
  /// the real project.
  final bool useEmulator;

  /// Emulator host. Use the computer's LAN address to test from phones.
  final String emulatorHost;

  /// reCAPTCHA v3 *site* key for App Check (public; the secret key is only
  /// entered in the Firebase console). Empty: App Check is not activated.
  final String appCheckSiteKey;

  bool get isConfigured => projectId.isNotEmpty;
}
