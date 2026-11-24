// Converts app models to and from Firestore documents. Field names follow
// the JSON in data/courses/* (docs/architecture.md §3 and §5), so the seed
// script (firebase/tools/seed.mjs) and the app read the same documents.
import 'package:bousla_engine/bousla_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';

/// Document ID of one question version, also used for its answer key.
String questionDocId(String questionId, int version) =>
    '${questionId}_v$version';

/// Document ID of one participant's answer to one question version. The
/// security rules check this exact shape.
String responseDocId(String participantId, String questionId, int version) =>
    '${participantId}_${questionDocId(questionId, version)}';

Map<String, dynamic> withId(DocumentSnapshot<Map<String, dynamic>> doc) => {
      ...?doc.data(),
      'id': doc.id,
    };

Course courseFromDoc(String id, Map<String, dynamic> data) => Course(
      id: id,
      name: LocalizedText.fromJson(data['name'] as Map<String, dynamic>),
      ownerId: data['owner_id'] as String?,
    );

String statusToJson(ReviewStatus status) => switch (status) {
      ReviewStatus.pendingReview => 'pending_review',
      ReviewStatus.approved => 'approved',
      ReviewStatus.rejected => 'rejected',
    };

String sourceToJson(ContentSource source) => switch (source) {
      ContentSource.team => 'team',
      ContentSource.aiDraft => 'ai_draft',
      ContentSource.instructor => 'instructor',
    };

List<String> languagesToJson(Set<Language> languages) => [
      for (final l in Language.values)
        if (languages.contains(l)) l.name
    ];

Map<String, String> _text(LocalizedText t) => {'ar': t.ar, 'en': t.en};

/// The latest version of each question, in a stable order (by ID).
List<QuestionView> latestVersions(Iterable<QuestionView> all) {
  final byId = <String, QuestionView>{};
  for (final q in all) {
    final current = byId[q.id];
    if (current == null || q.version > current.version) byId[q.id] = q;
  }
  return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
}

/// A question built from what the instructor entered (text trimmed).
QuestionView buildQuestion({
  required String id,
  required int version,
  required QuestionDraft draft,
  required ReviewStatus status,
  required ContentSource source,
  required bool edited,
  required String? sourceLocation,
  required RejectionReason? rejectionReason,
  String? sourceMaterialId,
}) =>
    QuestionView(
      question: Question(
        id: id,
        version: version,
        conceptIds: List.unmodifiable(draft.conceptIds),
        optionIds: [for (final o in draft.options) o.id],
        status: status,
      ),
      prompt:
          LocalizedText(ar: draft.prompt.ar.trim(), en: draft.prompt.en.trim()),
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
      sourceMaterialId: sourceMaterialId,
      hiddenOptionLanguages: Set.unmodifiable(draft.hiddenOptionLanguages),
    );

/// Firestore document for [q]. Fields of [base] that the app does not model
/// (e.g. `difficulty`, `provenance.source_material_id`) are kept.
Map<String, dynamic> questionToJson(
  QuestionView q, {
  Map<String, dynamic>? base,
  String? reviewedBy,
}) {
  final baseProvenance = base?['provenance'] is Map
      ? Map<String, dynamic>.from(base!['provenance'] as Map)
      : <String, dynamic>{};
  return {
    ...?base,
    'id': q.id,
    'version': q.version,
    'type': 'multiple_choice',
    'concept_ids': q.conceptIds,
    'prompt': _text(q.prompt),
    'options': [
      for (final o in q.options) {'id': o.id, 'text': _text(o.text)},
    ],
    'hidden_option_languages': languagesToJson(q.hiddenOptionLanguages),
    'provenance': {
      ...baseProvenance,
      'source': sourceToJson(q.source),
      'status': statusToJson(q.status),
      'edited': q.edited,
      'rejection_reason': q.rejectionReason?.jsonValue,
      'source_location': q.sourceLocation,
      if (q.sourceMaterialId != null) 'source_material_id': q.sourceMaterialId,
      'reviewed_by': reviewedBy,
    },
  };
}

MaterialRecord materialFromJson(String id, Map<String, dynamic> json) =>
    MaterialRecord(
      id: id,
      fileName: json['file_name'] as String? ?? id,
      modelName: json['generated_by'] as String? ?? '',
      createdAt: json['created_at'] is Timestamp
          ? (json['created_at'] as Timestamp).toDate()
          : null,
      draftsSaved: (json['drafts_saved'] as num?)?.toInt() ?? 0,
      draftsDropped: (json['drafts_dropped'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> answerKeyToJson(
  String questionId,
  int version,
  String correctOptionId,
) =>
    {
      'question_id': questionId,
      'question_version': version,
      'correct_option_id': correctOptionId,
    };

AnswerKey answerKeyFromJson(Map<String, dynamic> json) => AnswerKey(
      questionId: json['question_id'] as String,
      questionVersion: json['question_version'] as int,
      correctOptionId: json['correct_option_id'] as String,
    );

Map<String, dynamic> sessionToJson(Session s) => {
      'code': s.code,
      'course_id': s.courseId,
      'owner_id': s.ownerId,
      'questions': [
        for (final q in s.questions)
          {'question_id': q.questionId, 'version': q.version},
      ],
      // Lets the security rules check that a response belongs to the session.
      'question_keys': [
        for (final q in s.questions) questionDocId(q.questionId, q.version),
      ],
      'status': s.status.name,
      'feedback_released': s.feedbackReleased,
    };

Session sessionFromDoc(String id, Map<String, dynamic> data) => Session(
      id: id,
      code: data['code'] as String,
      courseId: data['course_id'] as String,
      ownerId: data['owner_id'] as String,
      questions: [
        for (final q in data['questions'] as List)
          QuestionRef(
            (q as Map)['question_id'] as String,
            q['version'] as int,
          ),
      ],
      status: data['status'] == 'closed'
          ? SessionStatus.closed
          : SessionStatus.open,
      feedbackReleased: data['feedback_released'] == true,
    );

Map<String, dynamic> responseToJson(Response r) => {
      'participant_id': r.participantId,
      'question_id': r.questionId,
      'question_version': r.questionVersion,
      'selected_option_id': r.selectedOptionId,
      'display_language': r.displayLanguage.name,
      'free_text': null,
      'submitted_at': FieldValue.serverTimestamp(),
    };

Response responseFromJson(Map<String, dynamic> json) => Response(
      participantId: json['participant_id'] as String,
      questionId: json['question_id'] as String,
      questionVersion: json['question_version'] as int,
      selectedOptionId: json['selected_option_id'] as String,
      displayLanguage: Language.parse(json['display_language'] as String),
    );
