import 'package:bousla_engine/bousla_engine.dart';

/// "Test my understanding again" with AI: writes a short practice quiz for
/// one student on the concepts they reviewed ([buildPracticeQuizInstructions]).
/// Only concept IDs and names are sent; nothing about the student. What
/// comes back has passed the engine's guards ([parseQuestionDrafts]) but is
/// not reviewed by a person, so screens label it as AI practice.
abstract interface class PracticeQuizGenerator {
  /// The model that wrote the last quiz.
  String get modelName;

  /// Up to [followUpQuestionsPerConcept] questions per concept. Throws
  /// `QuestionGenerationException`.
  Future<List<GeneratedQuestion>> practiceQuestions({
    required List<DraftingConcept> concepts,
  });
}
