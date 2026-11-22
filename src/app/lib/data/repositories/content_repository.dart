import 'package:bousla_engine/bousla_engine.dart';

import '../models.dart';

/// Read access to course content.
///
/// Implementations: [InMemoryContentRepository] (development, no network)
/// and a Firestore implementation (owner: backend). Screens depend only on
/// this interface.
abstract interface class ContentRepository {
  Future<List<Course>> listCourses();

  Future<List<Concept>> listConcepts(String courseId);

  /// Students must only ever receive approved questions. Instructors can ask
  /// for all, to review drafts.
  Future<List<QuestionView>> listQuestions(
    String courseId, {
    bool approvedOnly = true,
  });

  Future<List<Resource>> listResources(
    String courseId, {
    bool approvedOnly = true,
  });

  /// Instructor only. The Firestore implementation is protected by security
  /// rules; never call this from the student portal.
  Future<List<AnswerKey>> answerKeys(String courseId);
}
