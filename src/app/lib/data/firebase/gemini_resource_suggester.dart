import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../ai/model_retry.dart';
import '../ai/question_generator.dart';
import '../ai/resource_suggester.dart';
import 'gemini_question_generator.dart';

/// [ResourceSuggester] on Gemini through Firebase AI Logic, with the same
/// models, fallback and error handling as [GeminiQuestionGenerator]. One
/// request for all chosen concepts (the free quota is 20 requests a day).
class GeminiResourceSuggester implements ResourceSuggester {
  GeminiResourceSuggester()
      : _models = [
          GeminiQuestionGenerator.defaultModel,
          if (GeminiQuestionGenerator.fallbackModel.isNotEmpty)
            GeminiQuestionGenerator.fallbackModel,
        ],
        _lastModel = GeminiQuestionGenerator.defaultModel;

  final List<String> _models;
  String _lastModel;

  @override
  String get modelName => _lastModel;

  @override
  Future<SuggestionParseResult> suggestResources({
    required List<Concept> concepts,
    int perConcept = 2,
    MaterialFile? material,
    String? request,
    ClassResourceFocus? focus,
  }) async {
    if (material != null && material.bytes.length > MaterialFile.maxBytes) {
      throw const QuestionGenerationException(GenerationProblem.fileTooLarge);
    }
    final instructions = buildResourceSuggestionInstructions(
      concepts: [
        for (final c in concepts) DraftingConcept(id: c.id, name: c.name),
      ],
      perConcept: perConcept,
      withMaterial: material != null,
      request: request,
      focus: focus,
    );
    final parts = <Part>[
      TextPart(instructions),
      if (material != null)
        switch (material.mimeType) {
          'application/pdf' =>
            InlineDataPart('application/pdf', material.bytes),
          'text/plain' => TextPart(
              'MATERIAL (${material.name}):\n'
              '${utf8.decode(material.bytes, allowMalformed: true)}',
            ),
          _ => throw const QuestionGenerationException(
              GenerationProblem.unsupportedFile,
            ),
        },
    ];
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
      retryAfter: (e) => e is QuestionGenerationException
          ? retryDelayFrom(e.detail)
          : null,
      call: (name) async {
        final r = await withGeminiErrors(() async {
          final model = FirebaseAI.googleAI().generativeModel(
            model: name,
            generationConfig: GenerationConfig(
              responseMimeType: 'application/json',
              responseJsonSchema: resourceSuggestionJsonSchema(),
              temperature: 0.4,
            ),
          );
          try {
            final res = await model
                .generateContent([Content.multi(parts)])
                .timeout(GeminiQuestionGenerator.timeout);
            debugPrint('Bousla AI: $name answered (resources)');
            return res;
          } on Object catch (e) {
            debugPrint('Bousla AI: $name failed (resources): $e');
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
    return parseResourceSuggestions(
      text,
      knownConceptIds: {for (final c in concepts) c.id},
      maxCount: concepts.length * perConcept,
      allowMaterial: material != null,
    );
  }
}
