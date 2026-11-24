import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';

String rejectionReasonText(AppLocalizations l, RejectionReason reason) =>
    switch (reason) {
      RejectionReason.incorrect => l.reviewReasonIncorrect,
      RejectionReason.unclear => l.reviewReasonUnclear,
      RejectionReason.translation => l.reviewReasonTranslation,
      RejectionReason.duplicate => l.reviewReasonDuplicate,
      RejectionReason.offTopic => l.reviewReasonOffTopic,
      RejectionReason.other => l.reviewReasonOther,
    };

String sourceText(AppLocalizations l, ContentSource source) =>
    switch (source) {
      ContentSource.aiDraft => l.reviewSourceAi,
      ContentSource.instructor => l.reviewSourceInstructor,
      ContentSource.team => l.reviewSourceTeam,
    };

String draftProblemText(AppLocalizations l, DraftProblem problem) =>
    switch (problem) {
      DraftProblem.promptArabicMissing => l.reviewProblemPromptArabicMissing,
      DraftProblem.promptEnglishMissing => l.reviewProblemPromptEnglishMissing,
      DraftProblem.promptArabicHasNoArabicLetters =>
        l.reviewProblemPromptArabicHasNoArabicLetters,
      DraftProblem.tooFewOptions => l.reviewProblemTooFewOptions,
      DraftProblem.optionTextMissing => l.reviewProblemOptionTextMissing,
      DraftProblem.duplicateOptionIds => l.reviewProblemDuplicateOptionIds,
      DraftProblem.correctOptionMissing => l.reviewProblemCorrectOptionMissing,
      DraftProblem.conceptMissing => l.reviewProblemConceptMissing,
      DraftProblem.unknownConcept => l.reviewProblemUnknownConcept,
      DraftProblem.allOptionLanguagesHidden =>
        l.reviewProblemAllOptionLanguagesHidden,
    };
