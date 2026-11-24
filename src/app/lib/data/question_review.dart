// Pure logic for reviewing questions: automatic checks and AI-draft
// statistics. No Flutter, no Firebase, so it is easy to test.
import 'package:bousla_engine/bousla_engine.dart';

import 'models.dart';

final _arabicLetter = RegExp(r'[؀-ۿ]');

/// Minimum and maximum number of answer options.
const minOptions = 2;
const maxOptions = 6;

/// Returns every problem found in [draft]; empty means it can be saved.
/// [knownConceptIds] are the concepts the question may be linked to.
List<DraftProblem> validateDraft(
  QuestionDraft draft,
  Set<String> knownConceptIds,
) {
  final problems = <DraftProblem>[];
  final ar = draft.prompt.ar.trim();
  final en = draft.prompt.en.trim();
  if (ar.isEmpty) {
    problems.add(DraftProblem.promptArabicMissing);
  } else if (!_arabicLetter.hasMatch(ar)) {
    problems.add(DraftProblem.promptArabicHasNoArabicLetters);
  }
  if (en.isEmpty) problems.add(DraftProblem.promptEnglishMissing);

  if (draft.options.length < minOptions) {
    problems.add(DraftProblem.tooFewOptions);
  }
  // Option text may be code such as "student_id" in both languages, so only
  // emptiness is checked here, not Arabic letters.
  if (draft.options.any(
    (o) => o.text.ar.trim().isEmpty || o.text.en.trim().isEmpty,
  )) {
    problems.add(DraftProblem.optionTextMissing);
  }
  final ids = draft.options.map((o) => o.id).toList();
  if (ids.toSet().length != ids.length) {
    problems.add(DraftProblem.duplicateOptionIds);
  }
  if (draft.correctOptionId == null || !ids.contains(draft.correctOptionId)) {
    problems.add(DraftProblem.correctOptionMissing);
  }
  // Hiding a language only changes what students see; the text above is
  // still required in both languages. Students must see at least one.
  if (draft.hiddenOptionLanguages.containsAll(Language.values)) {
    problems.add(DraftProblem.allOptionLanguagesHidden);
  }

  if (draft.conceptIds.isEmpty) {
    problems.add(DraftProblem.conceptMissing);
  } else if (draft.conceptIds.any((c) => !knownConceptIds.contains(c))) {
    problems.add(DraftProblem.unknownConcept);
  }
  return problems;
}

/// The next unused option ID: a, b, c, ...
String nextOptionId(Iterable<String> used) {
  final taken = used.toSet();
  for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code++) {
    final id = String.fromCharCode(code);
    if (!taken.contains(id)) return id;
  }
  var n = 1;
  while (taken.contains('o$n')) {
    n++;
  }
  return 'o$n';
}

/// [current] after the instructor ticks or unticks "hide [language]".
/// Hiding one language shows the other, so students always see one.
Set<Language> toggleHiddenLanguage(
  Set<Language> current,
  Language language,
  bool hidden,
) => hidden ? {language} : (Set.of(current)..remove(language));

/// What instructors decided about AI-drafted questions. Shown on the review
/// screen and usable as evidence of AI draft quality.
class AiReviewStats {
  const AiReviewStats({
    required this.total,
    required this.pending,
    required this.approvedAsIs,
    required this.approvedEdited,
    required this.rejected,
    required this.rejectionReasons,
  });

  final int total;
  final int pending;
  final int approvedAsIs;
  final int approvedEdited;
  final int rejected;

  /// Rejected questions per reason; those without a reason are not counted.
  final Map<RejectionReason, int> rejectionReasons;

  int get reviewed => total - pending;
}

/// Counts decisions on AI drafts in [questions] (one entry per question,
/// latest version).
AiReviewStats aiReviewStats(Iterable<QuestionView> questions) {
  var total = 0, pending = 0, asIs = 0, edited = 0, rejected = 0;
  final reasons = <RejectionReason, int>{};
  for (final q in questions) {
    if (q.source != ContentSource.aiDraft) continue;
    total++;
    switch (q.status) {
      case ReviewStatus.pendingReview:
        pending++;
      case ReviewStatus.approved:
        if (q.edited) {
          edited++;
        } else {
          asIs++;
        }
      case ReviewStatus.rejected:
        rejected++;
        final reason = q.rejectionReason;
        if (reason != null) reasons[reason] = (reasons[reason] ?? 0) + 1;
    }
  }
  return AiReviewStats(
    total: total,
    pending: pending,
    approvedAsIs: asIs,
    approvedEdited: edited,
    rejected: rejected,
    rejectionReasons: reasons,
  );
}
