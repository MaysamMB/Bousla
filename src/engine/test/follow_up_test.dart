import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

Question _q(String id, List<String> concepts,
        {ReviewStatus status = ReviewStatus.approved}) =>
    Question(
      id: id,
      version: 1,
      conceptIds: concepts,
      optionIds: const ['a', 'b'],
      status: status,
    );

void main() {
  group('selectFollowUpQuestions', () {
    final bank = [
      _q('pk_1', ['primary_key']),
      _q('pk_2', ['primary_key']),
      _q('pk_3', ['primary_key']),
      _q('pk_draft', ['primary_key'], status: ReviewStatus.pendingReview),
      _q('join_1', ['sql_join']),
      _q('both', ['primary_key', 'sql_join']),
    ];
    List<(String, String)> ids(List<FollowUpPick> p) =>
        [for (final x in p) (x.question.id, x.conceptId)];

    test('new questions only, at most two per concept, approved only', () {
      expect(
          ids(selectFollowUpQuestions(
              bank: bank, concepts: ['primary_key'], askedIds: {'pk_1'})),
          [('both', 'primary_key'), ('pk_2', 'primary_key')]);
    });

    test('never repeats an asked question, even when few are left', () {
      expect(
          ids(selectFollowUpQuestions(
              bank: bank,
              concepts: ['sql_join'],
              askedIds: {'join_1', 'both'})),
          isEmpty);
      expect(
          ids(selectFollowUpQuestions(
              bank: bank, concepts: ['sql_join'], askedIds: {'both'})),
          [('join_1', 'sql_join')]);
    });

    test('a question is used once, for the first concept it covers', () {
      expect(
          ids(selectFollowUpQuestions(
              bank: bank,
              concepts: ['primary_key', 'sql_join'],
              askedIds: const {})),
          [
            ('both', 'primary_key'),
            ('pk_1', 'primary_key'),
            ('join_1', 'sql_join'),
          ]);
    });

    test('no question for a concept: nothing for it', () {
      expect(
          selectFollowUpQuestions(
              bank: bank, concepts: ['normalization'], askedIds: const {}),
          isEmpty);
    });
  });

  group('compareFollowUp', () {
    test('1 of 3 before, 3 of 3 after: appears improved, +67 points', () {
      final c = compareFollowUp(
        concepts: ['primary_key'],
        before: {'primary_key': const Tally(1, 3)},
        grades: [
          for (var i = 0; i < 3; i++)
            const FollowUpGrade(conceptIds: ['primary_key'], correct: true),
        ],
      );
      final pk = c.concepts.single;
      expect(pk.before, const Tally(1, 3));
      expect(pk.after, const Tally(3, 3));
      expect(pk.change, FollowUpChange.appearsImproved);
      expect(pk.differencePoints, 67);
      expect(pk.mayStillNeedReview, isFalse);
      expect(c.assessed, 1);
      expect(c.appearsImproved.map((x) => x.conceptId), ['primary_key']);
      expect(c.mayStillNeedReview, isEmpty);
    });

    test('same, lower, no new evidence, no original evidence', () {
      final c = compareFollowUp(
        concepts: ['same', 'lower', 'none', 'new'],
        before: {
          'same': const Tally(1, 2),
          'lower': const Tally(2, 2),
          'none': const Tally(0, 3),
        },
        grades: const [
          FollowUpGrade(conceptIds: ['same'], correct: true),
          FollowUpGrade(conceptIds: ['same'], correct: false),
          FollowUpGrade(conceptIds: ['lower', 'new'], correct: false),
        ],
      );
      final byId = {for (final x in c.concepts) x.conceptId: x};
      expect(byId['same']!.change, FollowUpChange.aboutTheSame);
      expect(byId['same']!.differencePoints, 0);
      expect(byId['lower']!.change, FollowUpChange.appearsLower);
      expect(byId['lower']!.differencePoints, -100);
      expect(byId['none']!.change, FollowUpChange.noNewEvidence);
      expect(byId['none']!.differencePoints, isNull);
      expect(byId['none']!.mayStillNeedReview, isFalse);
      expect(byId['new']!.change, FollowUpChange.noOriginalEvidence);
      expect(c.assessed, 3);
      expect(c.mayStillNeedReview.map((x) => x.conceptId),
          ['same', 'lower', 'new']);
    });
  });
}
