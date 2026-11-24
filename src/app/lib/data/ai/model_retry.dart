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
/// - [retryable] false (e.g. a used-up daily limit) skips the retries.
/// - If every attempt failed this way, or a fallback failed for another
///   reason (e.g. that model is not offered for the project), the first
///   model's error is rethrown: its reason is the useful one.
Future<T> callWithModelFallback<T>({
  required List<String> models,
  required Future<T> Function(String model) call,
  required bool Function(Object error) isBusy,
  List<Duration> delays = const [Duration(seconds: 5)],
  Duration? Function(Object error)? retryAfter,
  bool Function(Object error)? retryable,
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
        // e.g. a used-up daily limit: go straight to the next model.
        if (retryable != null && !retryable(e)) break;
        // The service may say how long to wait ("Please retry in 17s",
        // seen live with a 5-requests-per-minute free tier); waiting less
        // only spends more of the same quota.
        if (m == 0 && a < delays.length) {
          await wait(retryAfter?.call(e) ?? delays[a]);
        }
      }
    }
  }
  // Report the first model's reason (busy, per-minute or daily limit).
  final first = firstBusy;
  if (first is QuestionGenerationException) throw first;
  throw QuestionGenerationException(GenerationProblem.busy, first?.toString());
}
