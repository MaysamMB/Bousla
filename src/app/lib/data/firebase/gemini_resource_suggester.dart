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
    Map<String, List<String>> questionsByConcept = const {},
    bool searchWeb = true,
  }) async {
    if (material != null && material.bytes.length > MaterialFile.maxBytes) {
      throw const QuestionGenerationException(GenerationProblem.fileTooLarge);
    }
    if (material == null && searchWeb) {
      try {
        final found = await _searchWeb(
          concepts: concepts,
          perConcept: perConcept,
          request: request,
          focus: focus,
          questionsByConcept: questionsByConcept,
        );
        if (found.accepted.isNotEmpty) return found;
        debugPrint('Bousla AI: web search gave no usable resources '
            '(${found.dropped}); describing resources instead');
      } on QuestionGenerationException catch (e) {
        // Out of quota: asking again (without search) would fail too.
        if (e.problem == GenerationProblem.dailyQuota ||
            e.problem == GenerationProblem.quota) {
          rethrow;
        }
        debugPrint('Bousla AI: web search failed (${e.problem} ${e.detail}); '
            'describing resources instead');
      }
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
      retryAfter: (e) =>
          e is QuestionGenerationException ? retryDelayFrom(e.detail) : null,
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
                .generateContent([Content.multi(parts)]).timeout(
                    GeminiQuestionGenerator.timeout);
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

  /// One request with Google Search grounding. The answer is free text (a
  /// search cannot be combined with a JSON schema); links are kept only for
  /// sites the search returned.
  Future<SuggestionParseResult> _searchWeb({
    required List<Concept> concepts,
    required int perConcept,
    required String? request,
    required ClassResourceFocus? focus,
    required Map<String, List<String>> questionsByConcept,
  }) async {
    final instructions = buildSearchedResourceInstructions(
      concepts: [
        for (final c in concepts) DraftingConcept(id: c.id, name: c.name),
      ],
      perConcept: perConcept,
      questionsByConcept: questionsByConcept,
      request: request,
      focus: focus,
    );
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
            tools: [Tool.googleSearch()],
            generationConfig: GenerationConfig(temperature: 0.3),
          );
          try {
            final res = await model
                .generateContent([Content.text(instructions)]).timeout(
                    GeminiQuestionGenerator.timeout);
            debugPrint('Bousla AI: $name answered (resources, web search)');
            return res;
          } on Object catch (e) {
            debugPrint('Bousla AI: $name failed (resources, web search): $e');
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
    final domains = searchedDomains([
      for (final c in response
              .candidates.firstOrNull?.groundingMetadata?.groundingChunks ??
          const <GroundingChunk>[])
        if (c.web case final w?) (title: w.title, domain: w.domain, uri: w.uri),
    ]);
    debugPrint('Bousla AI: web search sites: ${domains.join(', ')}');
    return parseSearchedResourceSuggestions(
      text,
      knownConceptIds: {for (final c in concepts) c.id},
      maxCount: concepts.length * perConcept,
      searchedDomains: domains,
    );
  }
}

/// The sites a web search returned, from its grounding chunks. With the
/// Gemini Developer API the chunk's title is the site's domain and its URI
/// a Google redirect, so the title (or domain) is used, and a URI only when
/// it is not a redirect.
Set<String> searchedDomains(
  Iterable<({String? title, String? domain, String? uri})> chunks,
) {
  final looksLikeDomain = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');
  final out = <String>{};
  for (final c in chunks) {
    for (final v in [c.domain, c.title]) {
      final d = v?.trim().toLowerCase() ?? '';
      if (looksLikeDomain.hasMatch(d)) out.add(d);
    }
    final host = Uri.tryParse(c.uri ?? '')?.host.toLowerCase() ?? '';
    if (host.isNotEmpty &&
        !host.endsWith('vertexaisearch.cloud.google.com') &&
        !host.endsWith('google.com')) {
      out.add(host);
    }
  }
  return out;
}
