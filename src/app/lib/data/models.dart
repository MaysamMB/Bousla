// App-level models. Educational models (Concept, Question, Response, ...)
// come from the engine package; these add what the screens need.
import 'package:bousla_engine/bousla_engine.dart';

class Course {
  const Course({required this.id, required this.name, this.ownerId});

  final String id;
  final LocalizedText name;

  /// Instructor UID. Null only for seed data.
  final String? ownerId;
}

class OptionView {
  const OptionView({required this.id, required this.text});

  final String id;
  final LocalizedText text;
}

/// A question as shown to students: bilingual text, no answer.
class QuestionView {
  const QuestionView({
    required this.question,
    required this.prompt,
    required this.options,
  });

  /// Engine model (IDs, version, concept mapping).
  final Question question;
  final LocalizedText prompt;
  final List<OptionView> options;

  String get id => question.id;
  int get version => question.version;

  factory QuestionView.fromJson(Map<String, dynamic> json) => QuestionView(
    question: Question.fromJson(json),
    prompt: LocalizedText.fromJson(json['prompt'] as Map<String, dynamic>),
    options: [
      for (final o in json['options'] as List)
        OptionView(
          id: (o as Map<String, dynamic>)['id'] as String,
          text: LocalizedText.fromJson(o['text'] as Map<String, dynamic>),
        ),
    ],
  );
}

/// Points to one version of one question used in a session.
class QuestionRef {
  const QuestionRef(this.questionId, this.version);

  final String questionId;
  final int version;

  @override
  bool operator ==(Object other) =>
      other is QuestionRef &&
      other.questionId == questionId &&
      other.version == version;

  @override
  int get hashCode => Object.hash(questionId, version);
}

enum SessionStatus { open, closed }

class Session {
  const Session({
    required this.id,
    required this.code,
    required this.courseId,
    required this.ownerId,
    required this.questions,
    required this.status,
    required this.feedbackReleased,
  });

  final String id;

  /// Short join code students type or scan. Not a secret, not personal.
  final String code;
  final String courseId;
  final String ownerId;
  final List<QuestionRef> questions;
  final SessionStatus status;
  final bool feedbackReleased;

  Session copyWith({SessionStatus? status, bool? feedbackReleased}) => Session(
    id: id,
    code: code,
    courseId: courseId,
    ownerId: ownerId,
    questions: questions,
    status: status ?? this.status,
    feedbackReleased: feedbackReleased ?? this.feedbackReleased,
  );
}

class SessionClosedException implements Exception {
  const SessionClosedException(this.sessionId);

  final String sessionId;

  @override
  String toString() => 'Session $sessionId is closed';
}

class DuplicateAnswerException implements Exception {
  const DuplicateAnswerException(this.questionId);

  final String questionId;

  @override
  String toString() => 'Question $questionId was already answered';
}
