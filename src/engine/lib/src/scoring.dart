import 'models.dart';

enum IgnoredReason {
  /// No question with this ID and version is known.
  unknownQuestion,

  /// The selected option is not one of the question's options.
  unknownOption,

  /// No answer key exists for this question version.
  missingKey,

  /// The participant already answered this question version.
  duplicate,
}

class ScoredResponse {
  const ScoredResponse(
      {required this.response,
      required this.question,
      required this.isCorrect});

  final Response response;
  final Question question;
  final bool isCorrect;
}

class IgnoredResponse {
  const IgnoredResponse(this.response, this.reason);

  final Response response;
  final IgnoredReason reason;
}

class ScoringResult {
  const ScoringResult({required this.scored, required this.ignored});

  final List<ScoredResponse> scored;

  /// Responses that could not be scored, with the reason. Never silently dropped.
  final List<IgnoredResponse> ignored;
}

String _versionKey(String questionId, int version) => '$questionId@$version';

/// Scores responses by comparing option IDs with answer keys.
///
/// Option text and display language are never used, so the same choice gives
/// the same result in Arabic and English. When a participant answered the same
/// question version more than once, the first response in [responses] counts.
ScoringResult scoreResponses({
  required Iterable<Response> responses,
  required Iterable<Question> questions,
  required Iterable<AnswerKey> keys,
}) {
  final questionsByKey = {
    for (final q in questions) _versionKey(q.id, q.version): q
  };
  final correctByKey = {
    for (final k in keys)
      _versionKey(k.questionId, k.questionVersion): k.correctOptionId
  };
  final seen = <String>{};
  final scored = <ScoredResponse>[];
  final ignored = <IgnoredResponse>[];

  for (final r in responses) {
    final key = _versionKey(r.questionId, r.questionVersion);
    final question = questionsByKey[key];
    if (question == null) {
      ignored.add(IgnoredResponse(r, IgnoredReason.unknownQuestion));
      continue;
    }
    if (!question.optionIds.contains(r.selectedOptionId)) {
      ignored.add(IgnoredResponse(r, IgnoredReason.unknownOption));
      continue;
    }
    final correct = correctByKey[key];
    if (correct == null) {
      ignored.add(IgnoredResponse(r, IgnoredReason.missingKey));
      continue;
    }
    if (!seen.add('${r.participantId}|$key')) {
      ignored.add(IgnoredResponse(r, IgnoredReason.duplicate));
      continue;
    }
    scored.add(ScoredResponse(
      response: r,
      question: question,
      isCorrect: r.selectedOptionId == correct,
    ));
  }
  return ScoringResult(scored: scored, ignored: ignored);
}
