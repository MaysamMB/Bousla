import 'question_generator.dart';

/// Calls [call] with each model in [models] in turn, retrying while the
/// service is temporarily busy (it was during the first live test on
/// 24 Nov: "This model is currently experiencing high demand").
///
/// - [isBusy] tells a temporary overload (or quota) error apart from others.
/// - The first model is tried `1 + delays.length` times, waiting [delays]
///   in between, or what [retryAfter] reads from the error; each fallback
///   model once.
/// - Other errors stop immediately and are rethrown.
/// - If every attempt was busy, or a fallback failed for another reason
///   (e.g. that model is not offered for the project), throws
///   [QuestionGenerationException] with [GenerationProblem.busy] and the
///   first error's message, which is the useful one.
Future<T> callWithModelFallback<T>({
  required List<String> models,
  required Future<T> Function(String model) call,
  required bool Function(Object error) isBusy,
  List<Duration> delays = const [Duration(seconds: 2), Duration(seconds: 5)],
  Duration? Function(Object error)? retryAfter,
  Future<void> Function(Duration) wait = Future<void>.delayed,
}) async {
  assert(models.isNotEmpty);
  Object? firstBusy;
  for (var m = 0; m < models.length; m++) {
    final attempts = m == 0 ? 1 + delays.length : 1;
    for (var a = 0; a < attempts; a++) {
      try {
        return await call(models[m]);
      } catch (e) {
        final busy = isBusy(e);
        if (!busy && m == 0) rethrow;
        firstBusy ??= e;
        if (!busy) break; // fallback model unusable: try the next one
        // The service may say how long to wait ("Please retry in 17s",
        // seen live with a 5-requests-per-minute free tier); waiting less
        // only spends more of the same quota.
        if (m == 0 && a < delays.length) {
          await wait(retryAfter?.call(e) ?? delays[a]);
        }
      }
    }
  }
  throw QuestionGenerationException(
    GenerationProblem.busy,
    firstBusy is QuestionGenerationException
        ? firstBusy.detail
        : firstBusy?.toString(),
  );
}
