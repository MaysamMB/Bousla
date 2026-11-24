/// Small helpers for reading a model's JSON answer. Internal to the engine
/// (not exported from `bousla_engine.dart`).
library;

/// Models sometimes wrap JSON in a ```json fence despite the schema.
String stripCodeFence(String text) {
  final t = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
  return fence.firstMatch(t)?.group(1) ?? t;
}
