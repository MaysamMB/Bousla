import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../app_services.dart';
import 'firebase_auth_service.dart';
import 'firebase_config.dart';
import 'firestore_content_repository.dart';
import 'firestore_session_repository.dart';
import 'gemini_question_generator.dart';

/// Connects to Firebase and returns services backed by Firestore.
Future<AppServices> firebaseServices(FirebaseConfig config) async {
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: config.apiKey,
      appId: config.appId,
      messagingSenderId: config.messagingSenderId,
      projectId: config.projectId,
      authDomain: config.authDomain.isEmpty ? null : config.authDomain,
    ),
  );
  // App Check proves requests come from our web app, so nobody can use the
  // project's Gemini quota with the (public) web settings. Not used with the
  // emulators. Enforcement is switched on in the Firebase console.
  if (!config.useEmulator && config.appCheckSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(config.appCheckSiteKey),
    );
  }
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;
  if (config.useEmulator) {
    await auth.useAuthEmulator(config.emulatorHost, 9099);
    db.useFirestoreEmulator(config.emulatorHost, 8080);
  }
  final authService = FirebaseAuthService(auth);
  return AppServices(
    auth: authService,
    content: FirestoreContentRepository(
      db,
      currentUserId: () => auth.currentUser?.uid,
    ),
    sessions: FirestoreSessionRepository(
      db,
      ensureParticipant: authService.ensureParticipant,
    ),
    questionGenerator: GeminiQuestionGenerator(),
  );
}
