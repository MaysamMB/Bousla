import 'package:bousla_engine/bousla_engine.dart';

/// The model's raw answer for one session and the model that wrote it.
/// Not checked yet: [resolveExplanations] (engine) runs the guards.
class ExplainerAnswer {
  const ExplainerAnswer({required this.text, required this.model});

  final String text;
  final String model;
}

/// AI level 2: asks a model to explain the engine's results in words.
///
/// ONE request per session with all unique anonymous profiles
/// ([groupProfiles]); never one per student, never with names, UIDs or
/// answers. Called once, when the instructor publishes feedback.
abstract interface class FeedbackExplainer {
  /// Throws [QuestionGenerationException] (from `question_generator.dart`)
  /// when no model answered.
  Future<ExplainerAnswer> explain(List<ExplanationProfile> profiles);
}
