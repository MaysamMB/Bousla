import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

const _t = LocalizedText(ar: 'س', en: 's');

ConceptStanding _s(String id, MasteryState state, [int a = 4, int c = 3]) =>
    ConceptStanding(conceptId: id, state: state, attempts: a, correct: c);

CareerSkill _skill(String id, List<String> concepts, {bool essential = true}) =>
    CareerSkill(id: id, name: _t, essential: essential, conceptIds: concepts);

CareerRole _role(List<CareerSkill> skills) => CareerRole(
      id: 'r',
      title: _t,
      source: const CareerDataSource(
          kind: CareerSourceKind.teamDraft, name: 'Team draft'),
      skills: skills,
    );

void main() {
  group('careerGaps', () {
    test('each status follows the linked concepts', () {
      final report = careerGaps(
        _role([
          _skill('shown', ['a', 'b']),
          _skill('gap', ['a', 'c']),
          _skill('partial', ['a', 'd']),
          _skill('none', ['e']),
          _skill('outside', []),
        ]),
        {
          'a': _s('a', MasteryState.demonstratedMastery),
          'b': _s('b', MasteryState.demonstratedMastery),
          'c': _s('c', MasteryState.possibleDifficulty, 4, 1),
          'd': _s('d', MasteryState.emerging, 2, 1),
          'e': _s('e', MasteryState.insufficientEvidence, 1, 1),
        },
      );
      final byId = {for (final s in report.skills) s.skill.id: s};
      expect(byId['shown']!.status, SkillStatus.evidence);
      expect(byId['gap']!.status, SkillStatus.possibleGap);
      expect(byId['partial']!.status, SkillStatus.partial);
      expect(byId['none']!.status, SkillStatus.noEvidence);
      expect(byId['outside']!.status, SkillStatus.outsideBousla);
      expect(report.hasEvidence, isTrue);
    });

    test('a concept never assessed is "no evidence", not a gap', () {
      final report = careerGaps(_role([_skill('x', ['a'])]), {});
      expect(report.skills.single.status, SkillStatus.noEvidence);
      expect(report.skills.single.toWorkOn, ['a']);
      expect(report.hasEvidence, isFalse);
    });

    test('work on: review first, then concepts that need more evidence', () {
      final report = careerGaps(_role([_skill('x', ['a', 'b', 'c', 'd'])]), {
        'a': _s('a', MasteryState.emerging, 2, 1),
        'b': _s('b', MasteryState.possibleDifficulty, 4, 1),
        'c': _s('c', MasteryState.demonstratedMastery),
      });
      expect(report.skills.single.toWorkOn, ['b', 'a', 'd']);
    });

    test('essential first, then gaps first; otherwise the dataset order', () {
      final report = careerGaps(
        _role([
          _skill('opt-gap', ['a'], essential: false),
          _skill('ess-shown', ['b']),
          _skill('ess-gap', ['a']),
          _skill('ess-shown-2', ['b']),
        ]),
        {
          'a': _s('a', MasteryState.possibleDifficulty, 4, 1),
          'b': _s('b', MasteryState.demonstratedMastery),
        },
      );
      expect([for (final s in report.skills) s.skill.id],
          ['ess-gap', 'ess-shown', 'ess-shown-2', 'opt-gap']);
      expect(report.count(SkillStatus.possibleGap, essential: true), 1);
      expect(report.count(SkillStatus.possibleGap), 2);
    });
  });

  group('latestStandings', () {
    test('a later assessed result replaces an earlier one', () {
      final out = latestStandings([
        [_s('a', MasteryState.possibleDifficulty, 4, 1)],
        [_s('a', MasteryState.demonstratedMastery)],
      ]);
      expect(out['a']!.state, MasteryState.demonstratedMastery);
    });

    test('a later session without evidence does not hide an earlier result',
        () {
      final out = latestStandings([
        [_s('a', MasteryState.emerging, 2, 1)],
        [_s('a', MasteryState.insufficientEvidence, 1, 1)],
        [_s('b', MasteryState.insufficientEvidence, 0, 0)],
      ]);
      expect(out['a']!.state, MasteryState.emerging);
      expect(out['b']!.state, MasteryState.insufficientEvidence);
    });
  });

  test('reads a role from JSON; an unknown source kind is refused', () {
    final role = careerRoleFromJson({
      'id': 'db_dev',
      'title': {'ar': 'مطوّر قواعد بيانات', 'en': 'Database developer'},
      'source': {'kind': 'team_draft', 'name': 'Team draft'},
      'skills': [
        {
          'id': 'sql',
          'name': {'ar': 'SQL', 'en': 'SQL'},
          'essential': true,
          'concepts': ['sql_select'],
        },
      ],
    });
    expect(role.source.isDraft, isTrue);
    expect(role.skills.single.conceptIds, ['sql_select']);
    expect(
      () => careerRoleFromJson({
        'id': 'x',
        'title': {'ar': 'x', 'en': 'x'},
        'source': {'kind': 'guess', 'name': 'x'},
        'skills': [],
      }),
      throwsFormatException,
    );
  });
}
