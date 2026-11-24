import 'package:bousla_app/data/ai/model_retry.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:flutter_test/flutter_test.dart';

const _busy = QuestionGenerationException(
  GenerationProblem.busy,
  'Server Error [500]: This model is currently experiencing high demand.',
);

bool _isBusy(Object e) =>
    e is QuestionGenerationException && e.problem == GenerationProblem.busy;

void main() {
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
    expect(calls, ['main', 'main', 'main', 'backup']);
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
}
