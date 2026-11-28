import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';

import '../../../data/models.dart';

/// A student's AI practice quiz ("test my understanding again" with
/// Gemini), kept only in this browser: the questions the model wrote, the
/// student's answers and whether it is finished. Never sent to Firebase;
/// the instructor never sees it. The correct options are here because the
/// browser grades these practice questions itself: they are new questions
/// written for this student, not the instructor's question bank.
class PracticeAttempt {
  PracticeAttempt({
    required this.model,
    required this.conceptIds,
    required this.questions,
    Map<int, String>? answers,
    this.finished = false,
  }) : answers = answers ?? {};

  final String model;
  final List<String> conceptIds;
  final List<GeneratedQuestion> questions;

  /// Question index → chosen option ID. Set once per question.
  final Map<int, String> answers;
  bool finished;

  /// Question `i` as a [QuestionView] for the answering screen (prompt and
  /// options only).
  QuestionView view(int i) {
    final q = questions[i];
    return QuestionView(
      question: Question(
        id: 'practice_$i',
        version: 1,
        conceptIds: q.conceptIds,
        optionIds: [for (final o in q.options) o.id],
      ),
      prompt: q.prompt,
      options: [for (final o in q.options) OptionView(id: o.id, text: o.text)],
    );
  }

  /// One grade per answered question.
  List<FollowUpGrade> get grades => [
        for (final e in answers.entries)
          if (e.key >= 0 && e.key < questions.length)
            FollowUpGrade(
              conceptIds: questions[e.key].conceptIds,
              correct: questions[e.key].correctOptionId == e.value,
            ),
      ];

  String toJson() => jsonEncode({
        'model': model,
        'concept_ids': conceptIds,
        'finished': finished,
        'answers': {for (final e in answers.entries) '${e.key}': e.value},
        'questions': [
          for (final q in questions)
            {
              'concept_ids': q.conceptIds,
              'prompt': {'ar': q.prompt.ar, 'en': q.prompt.en},
              'options': [
                for (final o in q.options)
                  {'id': o.id, 'ar': o.text.ar, 'en': o.text.en},
              ],
              'correct': q.correctOptionId,
            },
        ],
      });

  /// Null when [raw] is missing or not a practice attempt.
  static PracticeAttempt? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final questions = [
        for (final q in j['questions'] as List)
          GeneratedQuestion(
            conceptIds: [for (final c in q['concept_ids'] as List) c as String],
            prompt: LocalizedText(
              ar: q['prompt']['ar'] as String,
              en: q['prompt']['en'] as String,
            ),
            options: [
              for (final o in q['options'] as List)
                GeneratedOption(
                  id: o['id'] as String,
                  text: LocalizedText(
                      ar: o['ar'] as String, en: o['en'] as String),
                ),
            ],
            correctOptionId: q['correct'] as String,
          ),
      ];
      if (questions.isEmpty) return null;
      return PracticeAttempt(
        model: j['model'] as String? ?? '',
        conceptIds: [for (final c in j['concept_ids'] as List) c as String],
        questions: questions,
        answers: {
          for (final e in (j['answers'] as Map).entries)
            int.parse(e.key as String): e.value as String,
        },
        finished: j['finished'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
