import 'package:bousla_engine/bousla_engine.dart';

import '../models.dart';
import '../repositories/content_repository.dart';
import 'sample_content.dart';

/// Development implementation backed by [sample_content.dart]. No network.
class InMemoryContentRepository implements ContentRepository {
  InMemoryContentRepository()
    : _course = Course(
        id: sampleCourse['id'] as String,
        name: LocalizedText.fromJson(
          sampleCourse['name'] as Map<String, dynamic>,
        ),
      ),
      _concepts = [for (final j in sampleConcepts) Concept.fromJson(j)],
      _questions = [for (final j in sampleQuestions) QuestionView.fromJson(j)],
      _resources = [for (final j in sampleResources) Resource.fromJson(j)],
      _keys = AnswerKey.listFromJson(sampleAnswerKeys);

  final Course _course;
  final List<Concept> _concepts;
  final List<QuestionView> _questions;
  final List<Resource> _resources;
  final List<AnswerKey> _keys;

  List<T> _forCourse<T>(String courseId, List<T> items) =>
      courseId == _course.id ? List.of(items) : <T>[];

  @override
  Future<List<Course>> listCourses() async => [_course];

  @override
  Future<List<Concept>> listConcepts(String courseId) async =>
      _forCourse(courseId, _concepts);

  @override
  Future<List<QuestionView>> listQuestions(
    String courseId, {
    bool approvedOnly = true,
  }) async => _forCourse(courseId, _questions)
      .where((q) => !approvedOnly || q.question.status == ReviewStatus.approved)
      .toList();

  @override
  Future<List<Resource>> listResources(
    String courseId, {
    bool approvedOnly = true,
  }) async => _forCourse(
    courseId,
    _resources,
  ).where((r) => !approvedOnly || r.status == ReviewStatus.approved).toList();

  @override
  Future<List<AnswerKey>> answerKeys(String courseId) async =>
      _forCourse(courseId, _keys);
}
