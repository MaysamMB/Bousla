import 'package:bousla_engine/bousla_engine.dart';

import '../models.dart';
import '../resource_review.dart';

/// Course content, and the instructor's review of it.
///
/// Implementations: [InMemoryContentRepository] (development, no network)
/// and a Firestore implementation (owner: backend). Screens depend only on
/// this interface.
abstract interface class ContentRepository {
  Future<List<Course>> listCourses();

  Future<List<Concept>> listConcepts(String courseId);

  /// The latest version of each question. Students must only ever receive
  /// approved questions. Instructors can ask for all, to review drafts.
  Future<List<QuestionView>> listQuestions(
    String courseId, {
    bool approvedOnly = true,
  });

  /// Exactly the question versions a session was created with, approved
  /// only, in the given order. Older versions stay available here after an
  /// edit, so a running session keeps the questions it started with.
  Future<List<QuestionView>> questionsForSession(
    String courseId,
    List<QuestionRef> refs,
  );

  /// Instructor only. Adds a question (when [QuestionDraft.id] is null) or
  /// edits one, together with its answer key.
  ///
  /// - New questions get `source: instructor`, version 1.
  /// - Editing an approved question creates version + 1 (it may already have
  ///   been answered in a session); pending or rejected questions are edited
  ///   in place.
  /// - Changing an AI draft marks it `edited`.
  /// - [status] sets the review status; when null, new questions are
  ///   pending and edited questions keep their status.
  ///
  /// Throws [InvalidDraftException] when the draft fails the automatic
  /// checks (approved concepts only), and [ArgumentError] for an unknown ID.
  Future<QuestionView> saveQuestion(
    String courseId,
    QuestionDraft draft, {
    ReviewStatus? status,
  });

  /// Instructor only. Hides (or shows again) the answer options in
  /// [language] for students, for one or many questions, all versions.
  /// Hiding one language shows the other, so students always see one. Not a
  /// content change: no new version, not marked edited. Unknown IDs are
  /// ignored.
  Future<void> setOptionLanguageHidden(
    String courseId,
    Iterable<String> questionIds,
    Language language, {
    required bool hidden,
  });

  /// Instructor only. Approves, rejects or restores (back to pending) one or
  /// many questions, all versions. [reason] is kept only when rejecting;
  /// [note] (the instructor's words) only with [RejectionReason.other].
  /// Unknown IDs are ignored.
  Future<void> setQuestionsStatus(
    String courseId,
    Iterable<String> questionIds,
    ReviewStatus status, {
    RejectionReason? reason,
    String? note,
  });

  /// Instructor only. Saves questions drafted by AI (level 1) as
  /// `source: ai_draft`, `pending_review`, with their answer keys and where
  /// in the material they come from. Also records the material's name (not
  /// the file, which is never stored) with how many drafts were kept or
  /// dropped. Drafts that fail [validateDraft] against the approved concepts
  /// are skipped. Returns the saved questions.
  Future<List<QuestionView>> saveAiDrafts(
    String courseId, {
    required String materialName,
    required String modelName,
    required List<GeneratedQuestion> drafts,
    int droppedByChecks = 0,
    int requested = 0,
    Map<String, int> droppedReasons = const {},
  });

  /// Instructor only. Materials questions were drafted from, newest first.
  Future<List<MaterialRecord>> listMaterials(String courseId);

  Future<List<Resource>> listResources(
    String courseId, {
    bool approvedOnly = true,
  });

  /// Instructor only. Adds a resource (when [ResourceDraft.id] is null) or
  /// completes / edits one. Saving approves it: the instructor wrote it or
  /// checked the link. Throws [InvalidResourceException] when
  /// [validateResourceDraft] fails, [ArgumentError] for an unknown ID.
  Future<Resource> saveResource(String courseId, ResourceDraft draft);

  /// Instructor only. Saves resource descriptions suggested by AI as
  /// `ai_draft`, `pending_review`, without links. Students never see them
  /// until the instructor adds a link and approves.
  Future<List<Resource>> saveAiResourceSuggestions(
    String courseId, {
    required String modelName,
    required List<ResourceSuggestion> suggestions,
  });

  /// Instructor only. Rejects, or restores to pending, resources. Approving
  /// goes through [saveResource], which checks the link. Unknown IDs are
  /// ignored.
  Future<void> setResourcesStatus(
    String courseId,
    Iterable<String> ids,
    ReviewStatus status,
  );

  /// Instructor only. The Firestore implementation is protected by security
  /// rules; never call this from the student portal.
  Future<List<AnswerKey>> answerKeys(String courseId);
}

class InvalidResourceException implements Exception {
  const InvalidResourceException(this.issues);

  final List<ResourceDraftIssue> issues;

  @override
  String toString() => 'InvalidResourceException($issues)';
}
