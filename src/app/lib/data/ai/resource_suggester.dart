import 'package:bousla_engine/bousla_engine.dart';

import 'question_generator.dart';

/// AI level 1, resources: real resources found by a web search (with their
/// links), or descriptions the instructor completes with a link. Either way
/// the instructor opens and approves each one before students see it.
abstract interface class ResourceSuggester {
  String get modelName;

  /// [material] is optional: with it, parts of the instructor's own file
  /// can also be suggested. [request]: what the instructor described in
  /// their own words. Without one, [focus] (aggregate results of the latest
  /// session) guides the suggestions. Throws [QuestionGenerationException].
  ///
  /// Without [material], the suggester may search the web for real
  /// resources ([searchWeb]); their links are kept only when the search
  /// itself returned their site ([parseSearchedResourceSuggestions]).
  /// [questionsByConcept]: prompts of approved questions per concept, used
  /// as search context (never answers).
  Future<SuggestionParseResult> suggestResources({
    required List<Concept> concepts,
    int perConcept,
    MaterialFile? material,
    String? request,
    ClassResourceFocus? focus,
    Map<String, List<String>> questionsByConcept,
    bool searchWeb,
  });
}
