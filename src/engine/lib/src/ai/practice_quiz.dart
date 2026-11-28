/// "Test my understanding again" with AI: a short practice quiz that Gemini
/// writes for one student, on the concepts they say they reviewed.
///
/// No network code here: the instructions sent to the model and the checks
/// on what comes back. Only concept IDs and names are sent, never a
/// student's name, ID, answers or results. The questions are checked by the
/// same guards as instructor drafts ([parseQuestionDrafts]) but are NOT
/// reviewed by a person before the student sees them, so the app labels
/// them as AI practice and the comparison as approximate.
library;

import '../follow_up.dart';
import 'question_drafting.dart';

/// Instructions for [perConcept] practice questions on each of [concepts].
String buildPracticeQuizInstructions({
  required List<DraftingConcept> concepts,
  int perConcept = followUpQuestionsPerConcept,
}) {
  final conceptLines = [
    for (final c in concepts) '- ${c.id}: ${c.name.en} / ${c.name.ar}',
  ].join('\n');
  final count = perConcept * concepts.length;
  return '''
You write a short self-check quiz for one university student who has just reviewed these concepts of an introductory database systems course:
$conceptLines

Write $count multiple-choice questions: $perConcept for each concept above. Rules:
1. Test understanding of the concept as taught in a standard introductory course, not trivia or memorised wording. Use only well-established facts.
2. Link every question to exactly the concept ID it tests, from the list above, and to nothing else.
3. Write every question and every option in BOTH Arabic (Modern Standard Arabic) and English, with the same meaning. In Arabic, a technical term may be followed by the English term in parentheses, for example: المفتاح الأساسي (Primary Key). Code, table and column names stay as they are in both languages.
4. Give 4 options with exactly one correct answer. Wrong options must be plausible to a student who has not understood the idea, not silly. Do not use "all of the above" or "none of the above". Vary the position of the correct answer.
5. The question text must not reveal the answer, and must not list the options: put them only in "options".
6. source_location is always "practice". difficulty is one of: basic, intermediate.

The student answers these questions on their own; no teacher checks them first, so each question must have one clearly correct answer.''';
}

/// The practice questions to use from the model's [result]: only questions
/// on one of [conceptIds], at most [perConcept] per concept (by the first
/// of its concepts in [conceptIds]), in the order of [conceptIds].
List<GeneratedQuestion> selectPracticeQuestions(
  DraftParseResult result, {
  required List<String> conceptIds,
  int perConcept = followUpQuestionsPerConcept,
}) {
  final out = <GeneratedQuestion>[];
  for (final id in conceptIds) {
    final mine = [
      for (final q in result.accepted)
        if (q.conceptIds.isNotEmpty &&
            conceptIds.firstWhere(q.conceptIds.contains, orElse: () => '') ==
                id)
          q,
    ];
    out.addAll(mine.take(perConcept));
  }
  return out;
}
