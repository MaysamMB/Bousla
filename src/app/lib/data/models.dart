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

/// Who wrote a piece of content (`provenance.source`).
enum ContentSource {
  /// Seed content written by the team.
  team,

  /// Drafted by AI from the instructor's material; needs human review.
  aiDraft,

  /// Written by the instructor by hand.
  instructor;

  static ContentSource parse(String? value) => switch (value) {
    'ai_draft' => ContentSource.aiDraft,
    'instructor' => ContentSource.instructor,
    _ => ContentSource.team,
  };
}

/// Why the instructor rejected an item (`provenance.rejection_reason`).
/// Optional; counted to measure the quality of AI drafts.
enum RejectionReason {
  incorrect,
  unclear,
  translation,
  duplicate,
  offTopic,
  other;

  String get jsonValue => switch (this) {
    RejectionReason.offTopic => 'off_topic',
    _ => name,
  };

  static RejectionReason? parse(String? value) {
    for (final r in RejectionReason.values) {
      if (r.jsonValue == value) return r;
    }
    return null;
  }
}

/// A question with its bilingual text and review information. Holds no
/// answer; keys are separate [AnswerKey]s that only the instructor can read.
class QuestionView {
  const QuestionView({
    required this.question,
    required this.prompt,
    required this.options,
    this.source = ContentSource.team,
    this.edited = false,
    this.rejectionReason,
    this.sourceLocation,
  });

  /// Engine model (IDs, version, concept mapping, review status).
  final Question question;
  final LocalizedText prompt;
  final List<OptionView> options;

  final ContentSource source;

  /// True when the instructor changed an AI draft before deciding on it.
  final bool edited;

  /// Only set while the question is rejected.
  final RejectionReason? rejectionReason;

  /// Where in the instructor's material an AI draft came from, e.g. "page 4".
  final String? sourceLocation;

  String get id => question.id;
  int get version => question.version;
  ReviewStatus get status => question.status;
  List<String> get conceptIds => question.conceptIds;

  QuestionView withStatus(ReviewStatus status, {RejectionReason? reason}) =>
      QuestionView(
        question: Question(
          id: question.id,
          version: question.version,
          conceptIds: question.conceptIds,
          optionIds: question.optionIds,
          status: status,
        ),
        prompt: prompt,
        options: options,
        source: source,
        edited: edited,
        rejectionReason: status == ReviewStatus.rejected ? reason : null,
        sourceLocation: sourceLocation,
      );

  factory QuestionView.fromJson(Map<String, dynamic> json) {
    final provenance = json['provenance'] is Map<String, dynamic>
        ? json['provenance'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return QuestionView(
      question: Question.fromJson(json),
      prompt: LocalizedText.fromJson(json['prompt'] as Map<String, dynamic>),
      options: [
        for (final o in json['options'] as List)
          OptionView(
            id: (o as Map<String, dynamic>)['id'] as String,
            text: LocalizedText.fromJson(o['text'] as Map<String, dynamic>),
          ),
      ],
      source: ContentSource.parse(provenance['source'] as String?),
      edited: provenance['edited'] == true,
      rejectionReason: RejectionReason.parse(
        provenance['rejection_reason'] as String?,
      ),
      sourceLocation: provenance['source_location'] as String?,
    );
  }
}

/// What the instructor fills in when adding or editing a question.
class QuestionDraft {
  const QuestionDraft({
    this.id,
    required this.conceptIds,
    required this.prompt,
    required this.options,
    required this.correctOptionId,
  });

  /// Null for a new question; the repository assigns the ID.
  final String? id;
  final List<String> conceptIds;
  final LocalizedText prompt;
  final List<OptionView> options;
  final String? correctOptionId;

  factory QuestionDraft.fromQuestion(QuestionView q, String? correctOptionId) =>
      QuestionDraft(
        id: q.id,
        conceptIds: List.of(q.conceptIds),
        prompt: q.prompt,
        options: List.of(q.options),
        correctOptionId: correctOptionId,
      );
}

/// Thrown when a [QuestionDraft] fails the automatic checks.
class InvalidDraftException implements Exception {
  const InvalidDraftException(this.problems);

  final List<DraftProblem> problems;

  @override
  String toString() => 'Invalid question draft: ${problems.join(', ')}';
}

/// Automatic checks on a question before it is saved. The same rules as
/// `src/ai/validate_data.py`, for questions only.
enum DraftProblem {
  promptArabicMissing,
  promptEnglishMissing,
  promptArabicHasNoArabicLetters,
  tooFewOptions,
  optionTextMissing,
  duplicateOptionIds,
  correctOptionMissing,
  conceptMissing,
  unknownConcept,
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
