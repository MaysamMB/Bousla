import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ClassInsights insightsFor(List<Response> rs, {int minGroupSize = 5}) =>
      buildClassInsights(
        masteriesByParticipant: masteriesFor(rs),
        concepts: testConcepts,
        minGroupSize: minGroupSize,
      );

  ConceptClassSummary summary(ClassInsights i, String id) =>
      i.concepts.firstWhere((c) => c.conceptId == id);

  test('no participants → zero count and every concept suppressed', () {
    final i = insightsFor([]);
    expect(i.participantCount, equals(0));
    expect(i.concepts.every((c) => c.suppressed), isTrue);
    expect(i.prerequisiteSignals, isEmpty);
  });

  test('fewer respondents than the minimum group size → suppressed, no counts',
      () {
    final rs = [
      for (var p = 1; p <= 4; p++) ...answers('p$p', 'primary_key', 0, 2)
    ];
    final s = summary(insightsFor(rs), 'primary_key');
    expect(s.suppressed, isTrue);
    expect(s.respondents, equals(4));
    expect(s.stateCounts, isEmpty);
    expect(s.pooledAccuracy, isNull);
  });

  test(
      'at the minimum group size → visible with state counts and pooled accuracy',
      () {
    final rs = [
      for (var p = 1; p <= 3; p++) ...answers('p$p', 'primary_key', 0, 2),
      for (var p = 4; p <= 5; p++) ...answers('p$p', 'primary_key', 3, 3),
    ];
    final s = summary(insightsFor(rs), 'primary_key');
    expect(s.suppressed, isFalse);
    expect(s.stateCounts[MasteryState.possibleDifficulty], equals(3));
    expect(s.stateCounts[MasteryState.demonstratedMastery], equals(2));
    expect(s.pooledAccuracy, closeTo(6 / 12, 1e-9));
    expect(s.difficultyShare, closeTo(0.6, 1e-9));
  });

  test('concepts are ordered by share of possible difficulty, suppressed last',
      () {
    final rs = [
      for (var p = 1; p <= 5; p++) ...answers('p$p', 'foreign_key', 0, 2),
      for (var p = 1; p <= 5; p++)
        ...answers('p$p', 'primary_key', p <= 2 ? 0 : 3, 3),
    ];
    final order = insightsFor(rs).concepts.map((c) => c.conceptId).toList();
    expect(order, equals(['foreign_key', 'primary_key', 'relational_model']));
  });

  test('counts participants whose difficulty may come from a prerequisite', () {
    final rs = [
      for (var p = 1; p <= 6; p++) ...answers('p$p', 'foreign_key', 0, 3),
      for (var p = 1; p <= 4; p++) ...answers('p$p', 'primary_key', 0, 2),
      for (var p = 5; p <= 6; p++) ...answers('p$p', 'primary_key', 3, 3),
    ];
    final signal = insightsFor(rs).prerequisiteSignals.single;
    expect(signal.conceptId, equals('foreign_key'));
    expect(signal.prerequisiteId, equals('primary_key'));
    expect(signal.participantsWithPossibleGap, equals(4));
    expect(signal.participantsStrugglingWithConcept, equals(6));
  });

  test('prerequisite signals are hidden when the concept is suppressed', () {
    final rs = [
      for (var p = 1; p <= 3; p++) ...answers('p$p', 'foreign_key', 0, 3),
      for (var p = 1; p <= 3; p++) ...answers('p$p', 'primary_key', 0, 2),
    ];
    expect(insightsFor(rs).prerequisiteSignals, isEmpty);
  });

  test('results are identical whatever language students answered in', () {
    List<Response> cls(Language lang) => [
          for (var p = 1; p <= 5; p++)
            ...answers('p$p', 'primary_key', p % 3, 3, lang: lang),
        ];
    final ar = summary(insightsFor(cls(Language.ar)), 'primary_key');
    final en = summary(insightsFor(cls(Language.en)), 'primary_key');
    expect(en.stateCounts, equals(ar.stateCounts));
    expect(en.pooledAccuracy, equals(ar.pooledAccuracy));
  });
}
