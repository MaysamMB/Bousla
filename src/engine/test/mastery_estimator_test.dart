import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  MasteryState s(int attempts, int correct) =>
      estimateMastery(ev(attempts, correct)).state;

  group('estimateMastery with starter thresholds', () {
    test('0 attempts → insufficient evidence', () {
      expect(s(0, 0), equals(MasteryState.insufficientEvidence));
    });

    test('1 attempt, even if correct → insufficient evidence', () {
      expect(s(1, 1), equals(MasteryState.insufficientEvidence));
      expect(s(1, 0), equals(MasteryState.insufficientEvidence));
    });

    test('2 attempts, 0 correct (0%) → possible difficulty', () {
      expect(s(2, 0), equals(MasteryState.possibleDifficulty));
    });

    test('2 attempts, 1 correct (exactly 50%) → emerging, not difficulty', () {
      expect(s(2, 1), equals(MasteryState.emerging));
    });

    test('2 attempts, 2 correct (100%) → emerging: mastery needs 3 attempts',
        () {
      expect(s(2, 2), equals(MasteryState.emerging));
    });

    test('3 attempts, 1 correct (33%) → possible difficulty', () {
      expect(s(3, 1), equals(MasteryState.possibleDifficulty));
    });

    test('3 attempts, 2 correct (67%) → emerging', () {
      expect(s(3, 2), equals(MasteryState.emerging));
    });

    test('3 attempts, 3 correct (100%) → demonstrated mastery', () {
      expect(s(3, 3), equals(MasteryState.demonstratedMastery));
    });

    test('4 attempts, 3 correct (exactly 75%) → demonstrated mastery', () {
      expect(s(4, 3), equals(MasteryState.demonstratedMastery));
    });

    test('4 attempts, 2 correct (exactly 50%) → emerging', () {
      expect(s(4, 2), equals(MasteryState.emerging));
    });

    test('keeps the evidence it was based on', () {
      final m = estimateMastery(ev(4, 3));
      expect(m.evidence.attempts, equals(4));
      expect(m.evidence.correct, equals(3));
    });
  });

  group('custom thresholds', () {
    test('are respected', () {
      const strict = MasteryThresholds(
          minAttemptsForAnyEstimate: 3, minAttemptsForMastery: 4);
      expect(estimateMastery(ev(2, 0), thresholds: strict).state,
          equals(MasteryState.insufficientEvidence));
      expect(estimateMastery(ev(3, 3), thresholds: strict).state,
          equals(MasteryState.emerging));
      expect(estimateMastery(ev(4, 4), thresholds: strict).state,
          equals(MasteryState.demonstratedMastery));
    });
  });
}
