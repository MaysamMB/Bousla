import 'package:bousla_app/features/instructor/sessions/concept_overview.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

ConceptClassSummary item(String id, {int n = 8, int difficulty = 0,
    int insufficient = 0, bool suppressed = false}) => ConceptClassSummary(
  conceptId: id, respondents: n, suppressed: suppressed,
  stateCounts: suppressed ? const {} : {
    MasteryState.possibleDifficulty: difficulty,
    MasteryState.insufficientEvidence: insufficient,
    MasteryState.emerging: n - difficulty - insufficient,
  },
);

ConceptOverview overview(List<ConceptClassSummary> items, Set<String> covered) =>
    buildConceptOverview(ClassInsights(participantCount: 8, minGroupSize: 5,
      concepts: items, prerequisiteSignals: const []), covered);

void main() {
  test('empty session has no visible concepts or priorities', () {
    final result = overview([], {});
    expect(result.visible, isEmpty);
    expect(result.coveredCount, 0);
    expect(result.hiddenCount, 0);
    expect(result.reviewCount, 0);
    expect(result.assessCount, 0);
  });
  test('suppressed, below-minimum and uncovered concepts never appear', () {
    final result = overview([
      item('hidden', n: 4, suppressed: true),
      item('tooSmall', n: 4, difficulty: 4),
      item('uncovered', difficulty: 8),
      item('visible', n: 5, difficulty: 3),
    ], {'hidden', 'tooSmall', 'visible'});
    expect(result.visible.map((c) => c.conceptId), ['visible']);
    expect(result.coveredCount, 3);
    expect(result.hiddenCount, 2);
    expect(result.reviewCount, 1);
  });
  test('priority metrics count concepts and use mutually exclusive rules', () {
    final result = overview([
      item('review', difficulty: 4, insufficient: 4),
      item('assess', insufficient: 4),
      item('monitor', difficulty: 3, insufficient: 3),
    ], {'review', 'assess', 'monitor'});
    expect(result.reviewCount, 1);
    expect(result.assessCount, 1);
    expect(result.visible.length, 3);
  });
  test('sort by difficulty share, then ID, without mutating input', () {
    final input = [item('z', difficulty: 4), item('a', difficulty: 4),
      item('b', n: 5, difficulty: 4)];
    final result = overview(input, {'a', 'b', 'z'});
    expect(result.visible.map((c) => c.conceptId), ['b', 'a', 'z']);
    expect(input.map((c) => c.conceptId), ['z', 'a', 'b']);
  });
  test('summary counts foundation priorities even below half difficulty', () {
    final input = ClassInsights(participantCount: 12, minGroupSize: 5,
      concepts: [item('foundation', n: 12, difficulty: 5),
        item('dependent', n: 12, difficulty: 8)],
      prerequisiteSignals: const [PrerequisiteClassSignal(
        conceptId: 'dependent', prerequisiteId: 'foundation',
        participantsWithPossibleGap: 5, participantsStrugglingWithConcept: 8,
      )]);
    final result = buildConceptOverview(input, {'foundation', 'dependent'});
    expect(result.reviewCount, 2);
    expect(result.assessCount, 0);
  });
  test('summary counts all priorities rather than only the top three', () {
    final result = overview([for (var i = 0; i < 5; i++)
      item('c$i', difficulty: 5)], {'c0', 'c1', 'c2', 'c3', 'c4'});
    expect(result.reviewCount, 5);
  });
  test('covered concepts with no summary do not become visible', () {
    final result = overview([], {'missing'});
    expect(result.hiddenCount, 1);
    expect(result.visible, isEmpty);
  });
}
