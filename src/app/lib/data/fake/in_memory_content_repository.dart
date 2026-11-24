import 'package:bousla_engine/bousla_engine.dart';

import '../models.dart';
import '../question_review.dart';
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

  /// Every version of every question.
  final List<QuestionView> _questions;
  final List<Resource> _resources;

  /// Keys for every question version.
  final List<AnswerKey> _keys;
  var _nextInstructorQuestion = 1;

  List<T> _forCourse<T>(String courseId, List<T> items) =>
      courseId == _course.id ? List.of(items) : <T>[];

  /// The highest version of each question, in first-seen order.
  List<QuestionView> get _latest {
    final byId = <String, QuestionView>{};
    for (final q in _questions) {
      final current = byId[q.id];
      if (current == null || q.version > current.version) byId[q.id] = q;
    }
    return byId.values.toList();
  }

  void _checkCourse(String courseId) {
    if (courseId != _course.id) {
      throw ArgumentError.value(courseId, 'courseId', 'Unknown course');
    }
  }

  @override
  Future<List<Course>> listCourses() async => [_course];

  @override
  Future<List<Concept>> listConcepts(String courseId) async =>
      _forCourse(courseId, _concepts);

  @override
  Future<List<QuestionView>> listQuestions(
    String courseId, {
    bool approvedOnly = true,
  }) async => _forCourse(courseId, _latest)
      .where((q) => !approvedOnly || q.status == ReviewStatus.approved)
      .toList();

  @override
  Future<List<QuestionView>> questionsForSession(
    String courseId,
    List<QuestionRef> refs,
  ) async {
    final all = _forCourse(courseId, _questions);
    return [
      for (final ref in refs)
        ...all.where(
          (q) =>
              q.id == ref.questionId &&
              q.version == ref.version &&
              q.status == ReviewStatus.approved,
        ),
    ];
  }

  @override
  Future<QuestionView> saveQuestion(
    String courseId,
    QuestionDraft draft, {
    ReviewStatus? status,
  }) async {
    _checkCourse(courseId);
    final approvedConcepts = {
      for (final c in _concepts)
        if (c.status == ReviewStatus.approved) c.id,
    };
    final problems = validateDraft(draft, approvedConcepts);
    if (problems.isNotEmpty) throw InvalidDraftException(problems);

    final draftId = draft.id;
    if (draftId == null) {
      final created = _build(
        id: 'instr_q_${_nextInstructorQuestion++}',
        version: 1,
        draft: draft,
        status: status ?? ReviewStatus.pendingReview,
        source: ContentSource.instructor,
        edited: false,
        sourceLocation: null,
        rejectionReason: null,
        hiddenOptionLanguages: draft.hiddenOptionLanguages,
      );
      _questions.add(created);
      _setKey(created.id, 1, draft.correctOptionId!);
      return created;
    }

    final existing = _latest.where((q) => q.id == draftId).firstOrNull;
    if (existing == null) {
      throw ArgumentError.value(draftId, 'draft.id', 'Unknown question');
    }
    final oldKey = _keyFor(existing.id, existing.version);
    final changed = !sameQuestionContent(existing, oldKey, draft);
    final newVersion = changed && existing.status == ReviewStatus.approved
        ? existing.version + 1
        : existing.version;
    final newStatus = status ?? existing.status;
    final saved = _build(
      id: existing.id,
      version: newVersion,
      draft: draft,
      status: newStatus,
      source: existing.source,
      edited:
          existing.edited ||
          (changed && existing.source == ContentSource.aiDraft),
      sourceLocation: existing.sourceLocation,
      rejectionReason: newStatus == ReviewStatus.rejected
          ? existing.rejectionReason
          : null,
      hiddenOptionLanguages: draft.hiddenOptionLanguages,
    );
    final index = _questions.indexWhere(
      (q) => q.id == existing.id && q.version == existing.version,
    );
    if (newVersion == existing.version) {
      _questions[index] = saved; // edited in place, keeps its position
    } else {
      _questions.insert(index + 1, saved); // old version stays for sessions
    }
    // A display setting, not content: applies to every version.
    _applyHidden({saved.id}, saved.hiddenOptionLanguages);
    _setKey(saved.id, saved.version, draft.correctOptionId!);
    return saved;
  }

  @override
  Future<void> setOptionLanguageHidden(
    String courseId,
    Iterable<String> questionIds,
    Language language, {
    required bool hidden,
  }) async {
    if (courseId != _course.id) return;
    final ids = questionIds.toSet();
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (ids.contains(q.id)) {
        _questions[i] = q.withHiddenOptionLanguages(
          toggleHiddenLanguage(q.hiddenOptionLanguages, language, hidden),
        );
      }
    }
  }

  void _applyHidden(Set<String> ids, Set<Language> hidden) {
    for (var i = 0; i < _questions.length; i++) {
      if (ids.contains(_questions[i].id)) {
        _questions[i] = _questions[i].withHiddenOptionLanguages(hidden);
      }
    }
  }

  @override
  Future<void> setQuestionsStatus(
    String courseId,
    Iterable<String> questionIds,
    ReviewStatus status, {
    RejectionReason? reason,
  }) async {
    if (courseId != _course.id) return;
    final ids = questionIds.toSet();
    for (var i = 0; i < _questions.length; i++) {
      if (ids.contains(_questions[i].id)) {
        _questions[i] = _questions[i].withStatus(status, reason: reason);
      }
    }
  }

  /// Material records saved by [saveAiDrafts] (names and counts only).
  final materials = <Map<String, Object?>>[];
  var _nextAiQuestion = 1;

  @override
  Future<List<QuestionView>> saveAiDrafts(
    String courseId, {
    required String materialName,
    required String modelName,
    required List<GeneratedQuestion> drafts,
    int droppedByChecks = 0,
  }) async {
    _checkCourse(courseId);
    final approvedConcepts = {
      for (final c in _concepts)
        if (c.status == ReviewStatus.approved) c.id,
    };
    final saved = <QuestionView>[];
    var skipped = 0;
    for (final g in drafts) {
      final draft = draftFromGenerated(g);
      if (validateDraft(draft, approvedConcepts).isNotEmpty) {
        skipped++;
        continue;
      }
      final q = _build(
        id: 'ai_q_${_nextAiQuestion++}',
        version: 1,
        draft: draft,
        status: ReviewStatus.pendingReview,
        source: ContentSource.aiDraft,
        edited: false,
        sourceLocation: g.sourceLocation,
        rejectionReason: null,
        hiddenOptionLanguages: const {},
      );
      _questions.add(q);
      _setKey(q.id, 1, draft.correctOptionId!);
      saved.add(q);
    }
    materials.add({
      'file_name': materialName,
      'generated_by': modelName,
      'drafts_saved': saved.length,
      'drafts_dropped': droppedByChecks + skipped,
    });
    return saved;
  }

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

  String? _keyFor(String id, int version) => _keys
      .where((k) => k.questionId == id && k.questionVersion == version)
      .firstOrNull
      ?.correctOptionId;

  void _setKey(String id, int version, String correctOptionId) {
    _keys
      ..removeWhere((k) => k.questionId == id && k.questionVersion == version)
      ..add(
        AnswerKey(
          questionId: id,
          questionVersion: version,
          correctOptionId: correctOptionId,
        ),
      );
  }

  static QuestionView _build({
    required String id,
    required int version,
    required QuestionDraft draft,
    required ReviewStatus status,
    required ContentSource source,
    required bool edited,
    required String? sourceLocation,
    required RejectionReason? rejectionReason,
    required Set<Language> hiddenOptionLanguages,
  }) => QuestionView(
    question: Question(
      id: id,
      version: version,
      conceptIds: List.unmodifiable(draft.conceptIds),
      optionIds: [for (final o in draft.options) o.id],
      status: status,
    ),
    prompt: LocalizedText(
      ar: draft.prompt.ar.trim(),
      en: draft.prompt.en.trim(),
    ),
    options: [
      for (final o in draft.options)
        OptionView(
          id: o.id,
          text: LocalizedText(ar: o.text.ar.trim(), en: o.text.en.trim()),
        ),
    ],
    source: source,
    edited: edited,
    rejectionReason: rejectionReason,
    sourceLocation: sourceLocation,
    hiddenOptionLanguages: Set.unmodifiable(hiddenOptionLanguages),
  );
}
