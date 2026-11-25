import 'package:bousla_app/features/instructor/sessions/live_insights.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _pk = Concept(
  id: 'pk',
  name: LocalizedText(
    ar: 'المفتاح الأساسي',
    en: 'Primary key',
  ),
);

const _fk = Concept(
  id: 'fk',
  name: LocalizedText(
    ar: 'المفتاح الأجنبي',
    en: 'Foreign key',
  ),
  prerequisites: ['pk'],
);

const _questions = [
  Question(id: 'q1', version: 1, conceptIds: ['pk'], optionIds: ['a', 'b']),
  Question(id: 'q2', version: 1, conceptIds: ['pk'], optionIds: ['a', 'b']),
  Question(id: 'q3', version: 1, conceptIds: ['fk'], optionIds: ['a', 'b']),
  Question(id: 'q4', version: 1, conceptIds: ['fk'], optionIds: ['a', 'b']),
];

final _keys = [
  for (final q in _questions)
    AnswerKey(
      questionId: q.id,
      questionVersion: 1,
      correctOptionId: 'a',
    ),
];

List<Response> _answers(
  int students,
  String option, {
  int offset = 0,
}) => [
  for (var s = offset; s < offset + students; s++)
    for (final q in _questions)
      Response(
        participantId: 'student$s',
        questionId: q.id,
        questionVersion: 1,
        selectedOptionId: option,
        displayLanguage: s.isEven ? Language.ar : Language.en,
      ),
];

ClassInsights _run(List<Response> responses) =>
    computeClassInsights(
      responses: responses,
      questions: _questions,
      keys: _keys,
      concepts: const [_pk, _fk],
    );

void main() {
  test('5 students all wrong: both concepts difficult', () {
    final insights = _run(_answers(5, 'b'));

    expect(insights.participantCount, 5);

    final fk = insights.concepts.firstWhere(
      (c) => c.conceptId == 'fk',
    );

    expect(fk.suppressed, isFalse);
    expect(fk.respondents, 5);
    expect(fk.pooledAccuracy, 0);
    expect(fk.stateCounts[MasteryState.possibleDifficulty], 5);

    final signal = insights.prerequisiteSignals.single;

    expect(signal.conceptId, 'fk');
    expect(signal.prerequisiteId, 'pk');
    expect(signal.participantsWithPossibleGap, 5);
  });

  test('2 students (under the minimum of 3): every concept hidden', () {
    final insights = _run(_answers(2, 'b'));

    expect(
      insights.concepts.every((c) => c.suppressed),
      isTrue,
    );

    expect(
      insights.concepts.every((c) => c.pooledAccuracy == null),
      isTrue,
    );

    expect(insights.prerequisiteSignals, isEmpty);
  });

  test('No answers yet', () {
    final insights = _run(const []);

    expect(insights.participantCount, 0);
    expect(insights.prerequisiteSignals, isEmpty);
  });

  test('Half correct and half wrong', () {
    final insights = _run([
      ..._answers(4, 'a'),
      ..._answers(4, 'b', offset: 4),
    ]);

    expect(insights.participantCount, 8);

    for (final concept in insights.concepts) {
      expect(concept.suppressed, isFalse);
      expect(concept.respondents, 8);
      expect(concept.pooledAccuracy, 0.5);

      expect(
        concept.stateCounts[MasteryState.possibleDifficulty],
        4,
      );

      expect(
        concept.stateCounts[MasteryState.emerging],
        4,
      );
    }
  });

  test('session overview: right answers overall, most wrong concepts first',
      () {
    // Student 0 wrong everywhere, student 1 right everywhere.
    final responses = [..._answers(1, 'b'), ..._answers(1, 'a', offset: 1)];
    final o = sessionOverview(
      responses: responses,
      questions: _questions,
      keys: _keys,
    );
    expect(o.answers, responses.length);
    expect(o.correct, responses.length ~/ 2);
    expect(o.percent, 50);
    expect(o.focusConceptIds, isNotEmpty);
    expect(o.focusConceptIds.length, lessThanOrEqualTo(3));
    final allRight = sessionOverview(
      responses: _answers(2, 'a'),
      questions: _questions,
      keys: _keys,
    );
    expect(allRight.focusConceptIds, isEmpty);
    expect(allRight.percent, 100);
  });
}
