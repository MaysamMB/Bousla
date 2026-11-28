/// "I've reviewed… test my understanding again": a short private
/// reassessment for one student, on new questions about the concepts they
/// say they reviewed.
///
/// Deterministic and pure. The student's review ticks only choose which
/// concepts are tested; they are never evidence. Improvement is read only
/// from the follow-up's graded answers against the original feedback's
/// counts, and worded as something that *appears* to have changed.
library;

import 'models.dart';

/// At most this many reassessment questions per concept.
const followUpQuestionsPerConcept = 2;

/// At most this many concepts in one follow-up (security rules check the
/// same limit), so at most `5 × 2 = 10` questions.
const maxFollowUpConcepts = 5;

/// At most this many questions in one follow-up (security rules check it).
const maxFollowUpQuestions = maxFollowUpConcepts * followUpQuestionsPerConcept;

/// One question reserved for a student's reassessment, and the concept it
/// was reserved for.
class FollowUpPick {
  const FollowUpPick(this.question, this.conceptId);

  final Question question;
  final String conceptId;
}

/// The questions reserved for one student's private reassessment, chosen
/// by the instructor app when it publishes feedback (it can read the
/// question bank; students cannot list it).
///
/// For each of [concepts] (the ones the feedback says may need review or
/// are still forming), up to [perConcept] approved questions from [bank]
/// (latest versions) that were **not** asked in the original session
/// ([askedIds], by question ID): never a repeat. A question is used once,
/// for the first concept in [concepts] it covers. A concept with no new
/// question gets none. Stable order: by concept, then question ID.
List<FollowUpPick> selectFollowUpQuestions({
  required List<Question> bank,
  required List<String> concepts,
  required Set<String> askedIds,
  int perConcept = followUpQuestionsPerConcept,
}) {
  final fresh = [
    for (final q in bank)
      if (q.status == ReviewStatus.approved && !askedIds.contains(q.id)) q,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final chosen = <FollowUpPick>[];
  final used = <String>{};
  for (final concept in concepts) {
    var n = 0;
    for (final q in fresh) {
      if (n >= perConcept) break;
      if (!q.conceptIds.contains(concept) || used.contains(q.id)) continue;
      chosen.add(FollowUpPick(q, concept));
      used.add(q.id);
      n++;
    }
  }
  return chosen;
}

/// One graded follow-up answer: whether it was correct, and the concepts of
/// its question.
class FollowUpGrade {
  const FollowUpGrade({required this.conceptIds, required this.correct});

  final List<String> conceptIds;
  final bool correct;
}

/// What the evidence shows for one concept, from the two results only.
enum FollowUpChange {
  /// A higher share correct in the follow-up than in the original.
  appearsImproved,

  /// The same share correct.
  aboutTheSame,

  /// A lower share correct.
  appearsLower,

  /// The follow-up had no graded answer on this concept.
  noNewEvidence,

  /// The original had no answer on this concept, so there is nothing to
  /// compare with.
  noOriginalEvidence,
}

/// Correct answers out of attempts.
class Tally {
  const Tally(this.correct, this.attempts);

  final int correct;
  final int attempts;

  /// Share correct, or null without attempts.
  double? get ratio => attempts == 0 ? null : correct / attempts;

  @override
  bool operator ==(Object other) =>
      other is Tally && other.correct == correct && other.attempts == attempts;

  @override
  int get hashCode => Object.hash(correct, attempts);

  @override
  String toString() => '$correct/$attempts';
}

class ConceptComparison {
  const ConceptComparison({
    required this.conceptId,
    required this.before,
    required this.after,
    required this.change,
  });

  final String conceptId;
  final Tally before;
  final Tally after;
  final FollowUpChange change;

  /// Percentage points from before to after (e.g. 1/3 → 3/3 is +67), or
  /// null when either side has no attempt.
  int? get differencePoints {
    final b = before.ratio, a = after.ratio;
    if (a == null || b == null) return null;
    return ((a - b) * 100).round();
  }

  /// Not every follow-up answer on it was correct: it may still need review.
  /// (Only said when there is follow-up evidence.)
  bool get mayStillNeedReview =>
      after.attempts > 0 && after.correct < after.attempts;
}

class FollowUpComparison {
  const FollowUpComparison(this.concepts);

  /// In the order of the reviewed concepts.
  final List<ConceptComparison> concepts;

  /// Concepts with at least one graded follow-up answer.
  int get assessed => concepts.where((c) => c.after.attempts > 0).length;

  List<ConceptComparison> get appearsImproved => [
        for (final c in concepts)
          if (c.change == FollowUpChange.appearsImproved) c,
      ];

  List<ConceptComparison> get mayStillNeedReview => [
        for (final c in concepts)
          if (c.mayStillNeedReview) c,
      ];
}

/// Compares, for each of [concepts], the original result ([before], the
/// feedback's correct/attempts per concept) with the follow-up's graded
/// answers ([grades]). A follow-up answer counts for every concept of its
/// question. Nothing here uses the review ticks.
FollowUpComparison compareFollowUp({
  required List<String> concepts,
  required Map<String, Tally> before,
  required List<FollowUpGrade> grades,
}) {
  return FollowUpComparison([
    for (final id in concepts)
      () {
        final b = before[id] ?? const Tally(0, 0);
        final mine = grades.where((g) => g.conceptIds.contains(id));
        final a = Tally(
          mine.where((g) => g.correct).length,
          mine.length,
        );
        final change = a.attempts == 0
            ? FollowUpChange.noNewEvidence
            : b.attempts == 0
                ? FollowUpChange.noOriginalEvidence
                : switch ((a.ratio! - b.ratio!).sign) {
                    > 0 => FollowUpChange.appearsImproved,
                    < 0 => FollowUpChange.appearsLower,
                    _ => FollowUpChange.aboutTheSame,
                  };
        return ConceptComparison(
          conceptId: id,
          before: b,
          after: a,
          change: change,
        );
      }(),
  ]);
}
