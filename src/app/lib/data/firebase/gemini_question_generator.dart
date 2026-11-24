import 'dart:async';
import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:firebase_ai/firebase_ai.dart';

import '../ai/question_generator.dart';

/// [QuestionGenerator] on Gemini through Firebase AI Logic (Gemini Developer
/// API, available on the Spark plan). No API key in the app: requests go
/// through Firebase. The material is sent with the request and not stored.
class GeminiQuestionGenerator implements QuestionGenerator {
  GeminiQuestionGenerator({String? model}) : modelName = model ?? defaultModel;

  /// Override at build time with --dart-define=GEMINI_MODEL=... if this model
  /// is not offered for the project (Firebase console → AI Logic).
  static const defaultModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  static const timeout = Duration(seconds: 120);

  @override
  final String modelName;

  @override
  Future<DraftParseResult> draftQuestions({
    required MaterialFile material,
    required List<Concept> concepts,
    required int count,
  }) async {
    if (material.bytes.length > MaterialFile.maxBytes) {
      throw const QuestionGenerationException(GenerationProblem.fileTooLarge);
    }
    final approved = [
      for (final c in concepts)
        if (c.status == ReviewStatus.approved) c,
    ];
    final model = FirebaseAI.googleAI().generativeModel(
      model: modelName,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseJsonSchema: questionDraftingJsonSchema(),
        temperature: 0.4,
      ),
    );
    final instructions = buildQuestionDraftingInstructions(
      count: count,
      concepts: [
        for (final c in approved) DraftingConcept(id: c.id, name: c.name),
      ],
    );
    final Part materialPart = switch (material.mimeType) {
      'application/pdf' => InlineDataPart('application/pdf', material.bytes),
      'text/plain' => TextPart(
          'MATERIAL (${material.name}):\n'
          '${utf8.decode(material.bytes, allowMalformed: true)}',
        ),
      _ => throw const QuestionGenerationException(
          GenerationProblem.unsupportedFile,
        ),
    };

    final GenerateContentResponse response;
    try {
      response = await model.generateContent([
        Content.multi([TextPart(instructions), materialPart]),
      ]).timeout(timeout);
    } on ServiceApiNotEnabled catch (e) {
      throw QuestionGenerationException(
        GenerationProblem.notEnabled,
        e.message,
      );
    } on QuotaExceeded catch (e) {
      throw QuestionGenerationException(GenerationProblem.quota, e.message);
    } on TimeoutException {
      throw const QuestionGenerationException(GenerationProblem.network);
    } on FirebaseAIException catch (e) {
      // Setup problems also arrive as generic server errors, e.g. right
      // after AI Logic is enabled, while permissions propagate.
      final setup = RegExp(
        'PERMISSION_DENIED|has not been used|is disabled|serviceusage',
        caseSensitive: false,
      ).hasMatch(e.message);
      throw QuestionGenerationException(
        setup ? GenerationProblem.notEnabled : GenerationProblem.unknown,
        e.message,
      );
    }
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const QuestionGenerationException(GenerationProblem.emptyAnswer);
    }
    return parseQuestionDrafts(
      text,
      knownConceptIds: {for (final c in approved) c.id},
      maxCount: count,
    );
  }
}
