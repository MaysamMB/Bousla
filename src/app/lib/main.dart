import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/firebase/firebase_config.dart';
import 'data/firebase/firebase_services.dart';

/// Runs on Firebase when a project is configured
/// (`--dart-define-from-file=firebase.env.json`), otherwise on the in-memory
/// repositories, which need no network. Screens are the same either way.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = FirebaseConfig.fromEnvironment();
  final services = config.isConfigured
      ? await firebaseServices(config)
      : AppServices.inMemory();
  runApp(BouslaApp(services: services));
}
