import 'package:bousla_engine/bousla_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';
import '../question_review.dart';
import '../repositories/content_repository.dart';
import 'firestore_codec.dart';

/// [ContentRepository] on Cloud Firestore. Layout (docs/architecture.md §6):
///
///   courses/{courseId}                        name, owner_id, languages
///   courses/{courseId}/concepts/{conceptId}
///   courses/{courseId}/questions/{id}_v{n}    one document per version
///   courses/{courseId}/answer_keys/{id}_v{n}  owner only (security rules)
///   courses/{courseId}/resources/{resourceId}
///
/// The review rules (versioning, `edited`, rejection reasons, hidden answer
/// language) are the same as in [InMemoryContentRepository]; both use
/// `question_review.dart`. Access control is in `firebase/firestore.rules`,
/// not here.
class FirestoreContentRepository implements ContentRepository {
  FirestoreContentRepository(this._db, {required this.currentUserId});

  final FirebaseFirestore _db;

  /// UID of the signed-in user, or null.
  final String? Function() currentUserId;

  CollectionReference<Map<String, dynamic>> _items(
    String courseId,
    String kind,
  ) =>
      _db.collection('courses').doc(courseId).collection(kind);

  @override
  Future<List<Course>> listCourses() async {
    final uid = currentUserId();
    if (uid == null) return const [];
    final snap =
        await _db.collection('courses').where('owner_id', isEqualTo: uid).get();
    final courses = [for (final d in snap.docs) courseFromDoc(d.id, d.data())];
    courses.sort((a, b) => a.id.compareTo(b.id));
    return courses;
  }

  @override
  Future<List<Concept>> listConcepts(String courseId) async {
    final snap = await _items(courseId, 'concepts').get();
    return [for (final d in snap.docs) Concept.fromJson(withId(d))];
  }

  /// Every version of every question (instructor only).
  Future<List<QuestionView>> _allVersions(String courseId) async {
    final snap = await _items(courseId, 'questions').get();
    return [for (final d in snap.docs) QuestionView.fromJson(d.data())];
  }

  @override
  Future<List<QuestionView>> listQuestions(
    String courseId, {
    bool approvedOnly = true,
  }) async =>
      latestVersions(await _allVersions(courseId))
          .where((q) => !approvedOnly || q.status == ReviewStatus.approved)
          .toList();

  @override
  Future<List<QuestionView>> questionsForSession(
    String courseId,
    List<QuestionRef> refs,
  ) async {
    // Students may read approved questions one by one, never list them.
    final docs = await Future.wait([
      for (final ref in refs)
        _items(courseId, 'questions')
            .doc(questionDocId(ref.questionId, ref.version))
            .get()
            .then<DocumentSnapshot<Map<String, dynamic>>?>((d) => d)
            .catchError(
              (Object _) => null,
              // Not approved (any more): the security rules refuse it.
              test: (e) =>
                  e is FirebaseException && e.code == 'permission-denied',
            ),
    ]);
    return [
      for (final d in docs)
        if (d != null && d.exists)
          if (QuestionView.fromJson(d.data()!) case final q
              when q.status == ReviewStatus.approved)
            q,
    ];
  }

  @override
  Future<QuestionView> saveQuestion(
    String courseId,
    QuestionDraft draft, {
    ReviewStatus? status,
  }) async {
    final approvedConcepts = {
      for (final c in await listConcepts(courseId))
        if (c.status == ReviewStatus.approved) c.id,
    };
    final problems = validateDraft(draft, approvedConcepts);
    if (problems.isNotEmpty) throw InvalidDraftException(problems);

    final questions = _items(courseId, 'questions');
    final keys = _items(courseId, 'answer_keys');
    final batch = _db.batch();
    final draftId = draft.id;

    if (draftId == null) {
      final id = 'instr_q_${questions.doc().id}';
      final created = buildQuestion(
        id: id,
        version: 1,
        draft: draft,
        status: status ?? ReviewStatus.pendingReview,
        source: ContentSource.instructor,
        edited: false,
        sourceLocation: null,
        rejectionReason: null,
      );
      batch.set(
        questions.doc(questionDocId(id, 1)),
        questionToJson(created, reviewedBy: _reviewer(created.status)),
      );
      batch.set(
        keys.doc(questionDocId(id, 1)),
        answerKeyToJson(id, 1, draft.correctOptionId!),
      );
      await batch.commit();
      return created;
    }

    final versions = await questions.where('id', isEqualTo: draftId).get();
    if (versions.docs.isEmpty) {
      throw ArgumentError.value(draftId, 'draft.id', 'Unknown question');
    }
    var existingDoc = versions.docs.first;
    for (final d in versions.docs) {
      if ((d.data()['version'] as int) >
          (existingDoc.data()['version'] as int)) {
        existingDoc = d;
      }
    }
    final existing = QuestionView.fromJson(existingDoc.data());
    final oldKey =
        await keys.doc(questionDocId(existing.id, existing.version)).get();
    final changed = !sameQuestionContent(
      existing,
      oldKey.data()?['correct_option_id'] as String?,
      draft,
    );
    final newVersion = changed && existing.status == ReviewStatus.approved
        ? existing.version + 1
        : existing.version;
    final newStatus = status ?? existing.status;
    final saved = buildQuestion(
      id: existing.id,
      version: newVersion,
      draft: draft,
      status: newStatus,
      source: existing.source,
      edited: existing.edited ||
          (changed && existing.source == ContentSource.aiDraft),
      sourceLocation: existing.sourceLocation,
      rejectionReason:
          newStatus == ReviewStatus.rejected ? existing.rejectionReason : null,
    );
    // Old versions stay untouched for running sessions, except the hidden
    // answer language: a display setting that applies to every version.
    for (final d in versions.docs) {
      batch.update(d.reference, {
        'hidden_option_languages': languagesToJson(draft.hiddenOptionLanguages),
      });
    }
    batch.set(
      questions.doc(questionDocId(saved.id, newVersion)),
      questionToJson(
        saved,
        base: existingDoc.data(),
        reviewedBy: newStatus == existing.status
            ? _reviewedBy(existingDoc.data())
            : _reviewer(newStatus),
      ),
    );
    batch.set(
      keys.doc(questionDocId(saved.id, newVersion)),
      answerKeyToJson(saved.id, newVersion, draft.correctOptionId!),
    );
    await batch.commit();
    return saved;
  }

  static String? _reviewedBy(Map<String, dynamic> data) {
    final provenance = data['provenance'];
    return provenance is Map ? provenance['reviewed_by'] as String? : null;
  }

  String? _reviewer(ReviewStatus status) =>
      status == ReviewStatus.pendingReview ? null : currentUserId();

  /// Every version document of the given questions.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _versionDocs(
    String courseId,
    Iterable<String> questionIds,
  ) async {
    final ids = questionIds.toSet().toList();
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    // Firestore allows at most 30 values in one whereIn.
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _items(
        courseId,
        'questions',
      ).where('id', whereIn: chunk).get();
      docs.addAll(snap.docs);
    }
    return docs;
  }

  /// Firestore allows at most 500 writes in one batch.
  Future<void> _updateAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, Object?> Function(Map<String, dynamic> data) changes,
  ) async {
    for (var i = 0; i < docs.length; i += 450) {
      final batch = _db.batch();
      for (final d in docs.skip(i).take(450)) {
        batch.update(d.reference, changes(d.data()));
      }
      await batch.commit();
    }
  }

  @override
  Future<void> setOptionLanguageHidden(
    String courseId,
    Iterable<String> questionIds,
    Language language, {
    required bool hidden,
  }) async {
    final docs = await _versionDocs(courseId, questionIds);
    await _updateAll(
      docs,
      (data) => {
        'hidden_option_languages': languagesToJson(
          toggleHiddenLanguage(
            QuestionView.fromJson(data).hiddenOptionLanguages,
            language,
            hidden,
          ),
        ),
      },
    );
  }

  @override
  Future<void> setQuestionsStatus(
    String courseId,
    Iterable<String> questionIds,
    ReviewStatus status, {
    RejectionReason? reason,
  }) async {
    final docs = await _versionDocs(courseId, questionIds);
    await _updateAll(
      docs,
      (_) => {
        'provenance.status': statusToJson(status),
        'provenance.rejection_reason':
            status == ReviewStatus.rejected ? reason?.jsonValue : null,
        'provenance.reviewed_by': _reviewer(status),
      },
    );
  }

  @override
  Future<List<QuestionView>> saveAiDrafts(
    String courseId, {
    required String materialName,
    required String modelName,
    required List<GeneratedQuestion> drafts,
    int droppedByChecks = 0,
  }) async {
    final approvedConcepts = {
      for (final c in await listConcepts(courseId))
        if (c.status == ReviewStatus.approved) c.id,
    };
    final questions = _items(courseId, 'questions');
    final keys = _items(courseId, 'answer_keys');
    final material = _items(courseId, 'materials').doc();
    final materialId = 'mat_${material.id}';
    final batch = _db.batch();
    final saved = <QuestionView>[];
    var skipped = 0;
    for (final g in drafts) {
      final draft = draftFromGenerated(g);
      if (validateDraft(draft, approvedConcepts).isNotEmpty) {
        skipped++;
        continue;
      }
      final id = 'ai_q_${questions.doc().id}';
      final q = buildQuestion(
        id: id,
        version: 1,
        draft: draft,
        status: ReviewStatus.pendingReview,
        source: ContentSource.aiDraft,
        edited: false,
        sourceLocation: g.sourceLocation,
        rejectionReason: null,
      );
      batch.set(
        questions.doc(questionDocId(id, 1)),
        questionToJson(
          q,
          base: {
            if (g.difficulty != null) 'difficulty': g.difficulty,
            'provenance': {
              'source_material_id': materialId,
              'generated_by': modelName,
            },
          },
        ),
      );
      batch.set(
        keys.doc(questionDocId(id, 1)),
        answerKeyToJson(id, 1, draft.correctOptionId!),
      );
      saved.add(q);
    }
    // Metadata only: the file itself is never stored.
    batch.set(_items(courseId, 'materials').doc(materialId), {
      'id': materialId,
      'file_name': materialName,
      'uploaded_by': currentUserId(),
      'generated_by': modelName,
      'status': 'ready_for_review',
      'drafts_saved': saved.length,
      'drafts_dropped': droppedByChecks + skipped,
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return saved;
  }

  @override
  Future<List<Resource>> listResources(
    String courseId, {
    bool approvedOnly = true,
  }) async {
    final snap = await _items(courseId, 'resources').get();
    return [
      for (final d in snap.docs)
        if (Resource.fromJson(withId(d)) case final r
            when !approvedOnly || r.status == ReviewStatus.approved)
          r,
    ];
  }

  @override
  Future<List<AnswerKey>> answerKeys(String courseId) async {
    final snap = await _items(courseId, 'answer_keys').get();
    return [for (final d in snap.docs) answerKeyFromJson(d.data())];
  }
}
