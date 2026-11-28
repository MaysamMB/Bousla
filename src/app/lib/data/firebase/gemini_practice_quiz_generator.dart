import 'package:bousla_engine/bousla_engine.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../ai/model_retry.dart';
import '../ai/practice_quiz_generator.dart';
import '../ai/question_generator.dart';
import 'gemini_question_generator.dart';

/// [PracticeQuizGenerator] on Gemini through Firebase AI Logic, with the same
/// models, fallback and error handling as question drafting. One request
/// per quiz; only concept IDs and names are sent.
class GeminiPracticeQuizGenerator implements PracticeQuizGenerator {
  GeminiPracticeQuizGenerator()
      : _models = [
          GeminiQuestionGenerator.defaultModel,
          if (GeminiQuestionGenerator.fallbackModel.isNotEmpty)
            GeminiQuestionGenerator.fallbackModel,
        ];

  final List<String> _models;
  String _lastModel = GeminiQuestionGenerator.defaultModel;

  @override
  String get modelName => _lastModel;

  @override
  Future<List<GeneratedQuestion>> practiceQuestions({
    required List<DraftingConcept> concepts,
  }) async {
    final instructions = buildPracticeQuizInstructions(concepts: concepts);
    final response = await callWithModelFallback(
      models: _models,
      isBusy: (e) =>
          e is QuestionGenerationException &&
          (e.problem == GenerationProblem.busy ||
              e.problem == GenerationProblem.quota ||
              e.problem == GenerationProblem.dailyQuota),
      retryable: (e) =>
          e is QuestionGenerationException &&
          e.problem != GenerationProblem.dailyQuota,
      retryAfter: (e) =>
          e is QuestionGenerationException ? retryDelayFrom(e.detail) : null,
      moveOn: isGeminiTimeout,
      call: (name) async {
        final r = await withGeminiErrors(() async {
          final model = FirebaseAI.googleAI().generativeModel(
            model: name,
            generationConfig: GenerationConfig(
              responseMimeType: 'application/json',
              responseJsonSchema: questionDraftingJsonSchema(),
              temperature: 0.4,
            ),
          );
          try {
            final out = await model
                .generateContent([Content.text(instructions)]).timeout(
                    GeminiQuestionGenerator.draftTimeout);
            debugPrint('Bousla AI practice: $name answered');
            return out;
          } on Object catch (e) {
            debugPrint('Bousla AI practice: $name failed: $e');
            rethrow;
          }
        });
        _lastModel = name;
        return r;
      },
    );
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const QuestionGenerationException(GenerationProblem.emptyAnswer);
    }
    final ids = [for (final c in concepts) c.id];
    return selectPracticeQuestions(
      parseQuestionDrafts(
        text,
        knownConceptIds: ids.toSet(),
        maxCount: maxFollowUpQuestions,
      ),
      conceptIds: ids,
    );
  }
}
