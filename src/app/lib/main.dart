import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';

void main() {
  // In-memory repositories until Firebase is connected (owner: backend).
  // Replace with Firestore implementations here; screens stay unchanged.
  runApp(BouslaApp(services: AppServices.inMemory()));
}
