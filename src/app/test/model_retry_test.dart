import 'package:bousla_app/data/ai/model_retry.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/firebase/gemini_question_generator.dart'
    show retryDelayFrom;
import 'package:flutter_test/flutter_test.dart';

const _busy = QuestionGenerationException(
  GenerationProblem.busy,
  'Server Error [500]: This model is currently experiencing high demand.',
);

bool _isBusy(Object e) =>
    e is QuestionGenerationException && e.problem == GenerationProblem.busy;

void main() {
  setUp(dailyLimitReached.clear);

  late List<String> calls;
  late List<Duration> waits;
  Future<void> wait(Duration d) async => waits.add(d);

  setUp(() {
    calls = [];
    waits = [];
  });

  test('succeeds after the first model was busy twice', () async {
    final result = await callWithModelFallback(
      models: ['main', 'backup'],
      isBusy: _isBusy,
      delays: const [Duration(seconds: 2), Duration(seconds: 5)],
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (calls.length < 3) throw _busy;
        return 'drafts from $m';
      },
    );
    expect(result, 'drafts from main');
    expect(calls, ['main', 'main', 'main']);
    expect(waits, const [Duration(seconds: 2), Duration(seconds: 5)]);
  });

  test('falls back to the second model when the first stays busy', () async {
    final result = await callWithModelFallback(
      models: ['main', 'backup'],
      isBusy: _isBusy,
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (m == 'main') throw _busy;
        return 'drafts from $m';
      },
    );
    expect(result, 'drafts from backup');
    expect(calls, ['main', 'main', 'backup']);
  });

  test('an unusable fallback model reports the original "busy" reason',
      () async {
    final error = await callWithModelFallback<String>(
      models: ['main', 'backup'],
      isBusy: _isBusy,
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (m == 'main') throw _busy;
        throw const QuestionGenerationException(
          GenerationProblem.unknown,
          'models/backup is not found',
        );
      },
    ).then<Object>((_) => 'no error', onError: (Object e) => e);
    expect(error, isA<QuestionGenerationException>());
    final e = error as QuestionGenerationException;
    expect(e.problem, GenerationProblem.busy);
    expect(e.detail, contains('high demand'));
  });

  test('other errors on the first model stop at once', () async {
    final error = await callWithModelFallback<String>(
      models: ['main', 'backup'],
      isBusy: _isBusy,
      wait: wait,
      call: (m) async {
        calls.add(m);
        throw const QuestionGenerationException(GenerationProblem.notEnabled);
      },
    ).then<Object>((_) => 'no error', onError: (Object e) => e);
    expect((error as QuestionGenerationException).problem,
        GenerationProblem.notEnabled);
    expect(calls, ['main']);
    expect(waits, isEmpty);
  });

  test('waits as long as the quota error asks', () async {
    const quota = QuestionGenerationException(
      GenerationProblem.quota,
      'Quota exceeded for metric: generate_content_free_tier_requests, '
      'limit: 5 ... Please retry in 16.952169101s.',
    );
    final result = await callWithModelFallback(
      models: ['main', 'backup'],
      isBusy: (e) => e is QuestionGenerationException,
      retryAfter: (e) =>
          retryDelayFrom((e as QuestionGenerationException).detail),
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (calls.length == 1) throw quota;
        return 'ok';
      },
    );
    expect(result, 'ok');
    expect(calls, ['main', 'main']);
    expect(waits, [const Duration(milliseconds: 17953)]);
  });

  test('retryDelayFrom ignores missing or very long delays', () {
    expect(retryDelayFrom('Please retry in 3s.'), const Duration(seconds: 4));
    expect(retryDelayFrom('Please retry in 120s.'), isNull);
    expect(retryDelayFrom('high demand'), isNull);
    expect(retryDelayFrom(null), isNull);
  });

  test('by default the first model gets one retry, then the fallback',
      () async {
    await callWithModelFallback(
      models: ['main', 'backup'],
      isBusy: _isBusy,
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (m == 'main') throw _busy;
        return 'ok';
      },
    );
    expect(calls, ['main', 'main', 'backup']);
  });

  test('a used-up daily limit is not retried: straight to the fallback',
      () async {
    const daily = QuestionGenerationException(
      GenerationProblem.dailyQuota,
      'limit: 20 ... requests per day ... Please retry in 17h9m28s.',
    );
    final result = await callWithModelFallback(
      models: ['main', 'backup'],
      isBusy: (e) => e is QuestionGenerationException,
      retryable: (e) =>
          (e as QuestionGenerationException).problem !=
          GenerationProblem.dailyQuota,
      wait: wait,
      call: (m) async {
        calls.add(m);
        if (m == 'main') throw daily;
        return 'ok';
      },
    );
    expect(result, 'ok');
    expect(calls, ['main', 'backup']);
    expect(waits, isEmpty);
    // "17h9m28s" is not read as 28 seconds.
    expect(retryDelayFrom(daily.detail), isNull);
  });

  test('both limits used up: the daily-limit reason is reported', () async {
    const daily =
        QuestionGenerationException(GenerationProblem.dailyQuota, 'per day');
    final error = await callWithModelFallback<String>(
      models: ['main', 'backup'],
      isBusy: (e) => e is QuestionGenerationException,
      retryable: (e) =>
          (e as QuestionGenerationException).problem !=
          GenerationProblem.dailyQuota,
      wait: wait,
      call: (m) async => throw daily,
    ).then<Object>((_) => 'no error', onError: (Object e) => e);
    expect(
      (error as QuestionGenerationException).problem,
      GenerationProblem.dailyQuota,
    );
  });

  test('a model whose daily limit is used up is skipped on the next call',
      () async {
    final used = <String>{};
    final called = <String>[];
    Future<String> run() => callWithModelFallback(
          models: const ['main', 'lite'],
          usedUp: used,
          isBusy: (_) => true,
          retryable: (e) =>
              (e as QuestionGenerationException).problem !=
              GenerationProblem.dailyQuota,
          wait: (_) async {},
          call: (m) async {
            called.add(m);
            if (m == 'main') {
              throw const QuestionGenerationException(
                GenerationProblem.dailyQuota,
              );
            }
            return 'ok from $m';
          },
        );
    expect(await run(), 'ok from lite');
    expect(called, ['main', 'lite']);
    called.clear();
    expect(await run(), 'ok from lite');
    expect(called, ['lite']); // main not tried again
    used.add('lite');
    await expectLater(
      run(),
      throwsA(isA<QuestionGenerationException>().having(
        (e) => e.problem,
        'problem',
        GenerationProblem.dailyQuota,
      )),
    );
    expect(called, ['lite']); // nothing sent
  });
}
