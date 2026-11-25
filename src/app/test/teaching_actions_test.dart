import 'package:bousla_app/features/instructor/sessions/teaching_actions.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

ConceptClassSummary concept(String id, {int respondents = 8,
    int difficulty = 0, int insufficient = 0, bool suppressed = false}) =>
    ConceptClassSummary(
      conceptId: id,
      respondents: respondents,
      suppressed: suppressed,
      stateCounts: suppressed ? const {} : {
        MasteryState.possibleDifficulty: difficulty,
        MasteryState.insufficientEvidence: insufficient,
        MasteryState.emerging: respondents - difficulty - insufficient,
      },
    );

PrerequisiteClassSignal signal(String related, String prerequisite,
        {int overlap = 5, int struggling = 6}) =>
    PrerequisiteClassSignal(
      conceptId: related,
      prerequisiteId: prerequisite,
      participantsWithPossibleGap: overlap,
      participantsStrugglingWithConcept: struggling,
    );

List<TeachingAction> actions(List<ConceptClassSummary> concepts, {
  List<PrerequisiteClassSignal> signals = const [],
  Set<String>? covered,
  int limit = 3,
}) => prioritizeTeachingActions(
      ClassInsights(participantCount: 8, minGroupSize: 5,
          concepts: concepts, prerequisiteSignals: signals),
      coveredConceptIds: covered ?? {for (final c in concepts) c.conceptId},
      limit: limit,
    );

void main() {
  test('empty evidence and no qualifying states give no suggestion', () {
    expect(actions([]), isEmpty);
    expect(actions([concept('a', difficulty: 3, insufficient: 3)]), isEmpty);
  });
  test('exactly half with difficulty qualifies, less does not', () {
    final result = actions([concept('a', difficulty: 4),
      concept('b', difficulty: 3)]);
    expect(result.single.conceptId, 'a');
    expect(result.single.kind, TeachingActionKind.reviewConcept);
    expect(result.single.affectedCount, 4);
    expect(result.single.groupCount, 8);
  });
  test('missing evidence leads to assessment, not reteaching', () {
    final result = actions([concept('a', insufficient: 5)]).single;
    expect(result.kind, TeachingActionKind.assessFurther);
    expect(result.affectedCount, 5);
  });
  test('suppressed, too-small and uncovered concepts are excluded', () {
    expect(actions([
      concept('a', respondents: 4, suppressed: true),
      concept('b', respondents: 4, difficulty: 4),
      concept('c', difficulty: 8),
    ], covered: {'a', 'b'}), isEmpty);
  });
  test('foundation first, deduplicated, followed by concept review', () {
    final result = actions([
      concept('fk', difficulty: 6), concept('pk', difficulty: 5),
      concept('other', insufficient: 5),
    ], signals: [signal('fk', 'pk'), signal('fk', 'pk')]);
    expect(result.map((a) => a.conceptId), ['pk', 'fk', 'other']);
    expect(result.first.kind, TeachingActionKind.reviewPrerequisite);
    expect(result.first.relatedConceptId, 'fk');
    expect(result.first.affectedCount, 5);
    expect(result.first.groupCount, 6);
  });
  test('small prerequisite overlap does not produce a foundation action', () {
    final result = actions([concept('fk', difficulty: 6),
      concept('pk', difficulty: 4)], signals: [signal('fk', 'pk', overlap: 4)]);
    expect(result.every((a) => a.kind != TeachingActionKind.reviewPrerequisite),
        isTrue);
  });
  test('uncovered or suppressed prerequisite never triggers a signal action', () {
    final result = actions([concept('fk', difficulty: 6),
      concept('pk', respondents: 4, suppressed: true)],
      signals: [signal('fk', 'pk')]);
    expect(result.single.conceptId, 'fk');
    expect(result.single.kind, TeachingActionKind.reviewConcept);
    expect(actions([concept('fk', difficulty: 6), concept('pk', difficulty: 5)],
      signals: [signal('fk', 'pk')], covered: {'fk'}).single.conceptId, 'fk');
  });
  test('stable ranking by difficulty share, ID tie-break, and limit', () {
    final result = actions([concept('z', difficulty: 4),
      concept('b', difficulty: 7), concept('a', difficulty: 4)], limit: 2);
    expect(result.map((a) => a.conceptId), ['b', 'a']);
    expect(actions([concept('a', difficulty: 8)], limit: 0), isEmpty);
  });
  test('assessment-only actions rank by insufficient-evidence share', () {
    final result = actions([concept('a', insufficient: 4),
      concept('z', insufficient: 7)]);
    expect(result.map((a) => a.conceptId), ['z', 'a']);
  });
}
