import 'package:bousla_engine/bousla_engine.dart';

import 'question_generator.dart';

/// AI level 1, resources: describes resources the instructor could add for
/// each concept (kind, where to look, search words, what it should cover),
/// never links. The result has passed [parseResourceSuggestions]; the
/// instructor finds each real resource and approves it.
abstract interface class ResourceSuggester {
  String get modelName;

  /// [material] is optional: with it, parts of the instructor's own file
  /// can also be suggested. [request]: what the instructor described in
  /// their own words. Without one, [focus] (aggregate results of the latest
  /// session) guides the suggestions. Throws [QuestionGenerationException].
  Future<SuggestionParseResult> suggestResources({
    required List<Concept> concepts,
    int perConcept,
    MaterialFile? material,
    String? request,
    ClassResourceFocus? focus,
  });
}
