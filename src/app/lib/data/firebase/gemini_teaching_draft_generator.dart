import 'package:firebase_ai/firebase_ai.dart';

import '../ai/model_retry.dart';
import '../ai/teaching_draft_generator.dart';
import '../ai/question_generator.dart';
import 'gemini_question_generator.dart';

/// Uses the existing Firebase AI Logic configuration. No API key or new SDK.
/// Called only after an instructor taps the strategy button.
class GeminiTeachingDraftGenerator implements TeachingDraftGenerator {
  @override
  Future<String> generate(String prompt) async {
    final models = [
      GeminiQuestionGenerator.defaultModel,
      if (GeminiQuestionGenerator.fallbackModel.isNotEmpty &&
          GeminiQuestionGenerator.fallbackModel !=
              GeminiQuestionGenerator.defaultModel)
        GeminiQuestionGenerator.fallbackModel,
    ];
    return callWithModelFallback<String>(
      models: models,
      delays: const [],
      isBusy: (e) =>
          e is QuestionGenerationException &&
          (e.problem == GenerationProblem.busy ||
              e.problem == GenerationProblem.quota ||
              e.problem == GenerationProblem.dailyQuota),
      call: (name) => withGeminiErrors(() async {
        final model = FirebaseAI.googleAI().generativeModel(
          model: name,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.2,
          ),
        );
        final response = await model.generateContent(
            [Content.text(prompt)]).timeout(const Duration(seconds: 12));
        return response.text ?? '';
      }),
    );
  }
}
