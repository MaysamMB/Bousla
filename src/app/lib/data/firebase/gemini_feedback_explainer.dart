import 'package:bousla_engine/bousla_engine.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../ai/feedback_explainer.dart';
import '../ai/model_retry.dart';
import '../ai/question_generator.dart';
import 'gemini_question_generator.dart';

/// [FeedbackExplainer] on Gemini through Firebase AI Logic, built like
/// [GeminiQuestionGenerator]: the same models, fallback, retries and error
/// handling. Only the anonymous profiles are sent.
class GeminiFeedbackExplainer implements FeedbackExplainer {
  GeminiFeedbackExplainer({String? model, String? fallback})
      : _models = [
          model ?? GeminiQuestionGenerator.defaultModel,
          if ((fallback ?? GeminiQuestionGenerator.fallbackModel).isNotEmpty)
            fallback ?? GeminiQuestionGenerator.fallbackModel,
        ];

  final List<String> _models;

  @override
  Future<ExplainerAnswer> explain(List<ExplanationProfile> profiles) async {
    final prompt = buildFeedbackExplanationPrompt(profiles);
    return callWithModelFallback(
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
      call: (name) => withGeminiErrors(() async {
        final model = FirebaseAI.googleAI().generativeModel(
          model: name,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseJsonSchema: feedbackExplanationJsonSchema(),
            temperature: 0.3,
          ),
        );
        try {
          final response = await model.generateContent(
              [Content.text(prompt)]).timeout(GeminiQuestionGenerator.timeout);
          debugPrint('Bousla AI feedback: $name answered');
          final text = response.text;
          if (text == null || text.trim().isEmpty) {
            throw const QuestionGenerationException(
              GenerationProblem.emptyAnswer,
            );
          }
          return ExplainerAnswer(text: text, model: name);
        } on Object catch (e) {
          debugPrint('Bousla AI feedback: $name failed: $e');
          rethrow;
        }
      }),
    );
  }
}
