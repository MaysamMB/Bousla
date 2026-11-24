import 'dart:async';
import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../ai/model_retry.dart';
import '../ai/question_generator.dart';

/// [QuestionGenerator] on Gemini through Firebase AI Logic (Gemini Developer
/// API, available on the Spark plan). No API key in the app: requests go
/// through Firebase. The material is sent with the request and not stored.
class GeminiQuestionGenerator implements QuestionGenerator {
  GeminiQuestionGenerator({String? model, String? fallback})
      : _models = [
          model ?? defaultModel,
          if ((fallback ?? fallbackModel).isNotEmpty) fallback ?? fallbackModel,
        ],
        _lastModel = model ?? defaultModel;

  /// Override at build time with --dart-define=GEMINI_MODEL=... if this model
  /// is not offered for the project (Firebase console → AI Logic).
  ///
  /// gemini-3.8-flash: the model Google's own error message pointed to on
  /// 24 Nov, when gemini-2.5-flash answered "no longer available to new
  /// users" and gemini-3.5-flash-lite kept answering "high demand".
  static const defaultModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.8-flash',
  );

  /// Tried when [defaultModel] stays busy (temporary overload or quota).
  /// --dart-define=GEMINI_FALLBACK_MODEL= (empty) turns it off.
  static const fallbackModel = String.fromEnvironment(
    'GEMINI_FALLBACK_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  static const timeout = Duration(seconds: 120);

  final List<String> _models;
  String _lastModel;

  /// The model that produced the last drafts (kept with them).
  @override
  String get modelName => _lastModel;

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

    final response = await callWithModelFallback(
      models: _models,
      isBusy: (e) =>
          e is QuestionGenerationException &&
          (e.problem == GenerationProblem.busy ||
              e.problem == GenerationProblem.quota),
      call: (name) async {
        final r = await _generate(name, [
          Content.multi([TextPart(instructions), materialPart]),
        ]);
        _lastModel = name;
        return r;
      },
    );
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

  /// One request to one model, logged to the browser console.
  Future<GenerateContentResponse> _logged(
    String name,
    List<Content> prompt,
  ) async {
    final model = FirebaseAI.googleAI().generativeModel(
      model: name,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseJsonSchema: questionDraftingJsonSchema(),
        temperature: 0.4,
      ),
    );
    try {
      final response = await model.generateContent(prompt).timeout(timeout);
      debugPrint('Bousla AI: $name answered');
      return response;
    } on Object catch (e) {
      // Browser console (F12) only: which model failed and why, so a
      // repeated "busy" can be diagnosed without showing raw errors.
      debugPrint('Bousla AI: $name failed: $e');
      rethrow;
    }
  }

  Future<GenerateContentResponse> _generate(
    String name,
    List<Content> prompt,
  ) async {
    try {
      return await _logged(name, prompt);
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
      // Temporary overload, as seen live: "Server Error [500] ... This model
      // is currently experiencing high demand".
      final busy = RegExp(
        r'high demand|overloaded|UNAVAILABLE|RESOURCE_EXHAUSTED|\[50[03]\]',
        caseSensitive: false,
      ).hasMatch(e.message);
      throw QuestionGenerationException(
        setup
            ? GenerationProblem.notEnabled
            : busy
                ? GenerationProblem.busy
                : GenerationProblem.unknown,
        e.message,
      );
    }
  }
}
