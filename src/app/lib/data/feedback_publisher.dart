// Publishing personal feedback (docs/architecture.md §7, Option A, and §9
// AI level 2). Runs in the instructor app:
//
//   responses, questions, keys, concepts, approved resources
//     → engine: scoreResponses → evidenceByParticipant → estimateAll
//               → analyzePrerequisites → recommend
//     → one anonymous profile per student, identical ones merged
//     → optional: ONE model request for all unique profiles, then the
//       engine's guards; template text whenever there is no valid AI text
//     → saveFeedback (all documents) → releaseFeedback
//
// The AI text only explains the engine's results; it never changes them.
import 'package:bousla_engine/bousla_engine.dart';

import 'ai/feedback_explainer.dart';
import 'ai/question_generator.dart';
import 'feedback.dart';
import 'models.dart';
import 'repositories/content_repository.dart';
import 'repositories/session_repository.dart';

/// One student's feedback before the explanation is added, with the
/// anonymous profile the explanation will be based on.
class ComputedFeedback {
  const ComputedFeedback({required this.feedback, required this.profile});

  /// Without [StudentFeedback.explanation].
  final StudentFeedback feedback;
  final ExplanationProfile profile;
}

/// The language a student mostly answered in. Participants have no stored
/// preferred language, so this is the most frequent `display_language` of
/// their responses; a tie goes to Arabic, the app's default language.
Language feedbackLanguage(Iterable<Response> responses) {
  var ar = 0;
  var en = 0;
  for (final r in responses) {
    r.displayLanguage == Language.ar ? ar++ : en++;
  }
  return en > ar ? Language.en : Language.ar;
}

/// Runs the engine for every participant with at least one scored answer.
/// Pure: no network, no Firebase. Keyed by participant ID.
///
/// Concepts covered: those of the session's questions plus their direct
/// prerequisites (so a prerequisite hint can name it), in course order.
Map<String, ComputedFeedback> computeFeedback({
  required List<Response> responses,
  required List<Question> questions,
  required List<AnswerKey> keys,
  required List<Concept> concepts,
  required List<Resource> resources,
}) {
  final byId = {for (final c in concepts) c.id: c};
  final sessionConcepts = {for (final q in questions) ...q.conceptIds};
  final covered = {
    ...sessionConcepts,
    for (final id in sessionConcepts) ...?byId[id]?.prerequisites,
  };
  final conceptIds = [
    for (final c in concepts)
      if (covered.contains(c.id)) c.id,
  ];
  final approved = [
    for (final r in resources)
      if (r.status == ReviewStatus.approved) r,
  ];

  final scored = scoreResponses(
    responses: responses,
    questions: questions,
    keys: keys,
  ).scored;
  final evidence = evidenceByParticipant(
    scored: scored,
    conceptIds: conceptIds,
  );

  final out = <String, ComputedFeedback>{};
  for (final entry in evidence.entries) {
    final participant = entry.key;
    final language = feedbackLanguage(
      responses.where((r) => r.participantId == participant),
    );
    final masteries = estimateAll(entry.value);
    final findings = analyzePrerequisites(
      masteries: masteries,
      concepts: concepts,
    );
    final recommendations = recommend(
      masteries: masteries,
      concepts: concepts,
      resources: approved,
      preferredLanguage: language,
    );
    out[participant] = ComputedFeedback(
      feedback: StudentFeedback(
        language: language,
        concepts: [
          for (final id in conceptIds)
            // .from keeps the concept's prerequisites for the knowledge map.
            if (masteries[id] case final m?) FeedbackConcept.from(byId[id]!, m),
        ],
        hints: [
          for (final f in findings)
            if (isStudentHint(f.signal))
              FeedbackHint(
                conceptId: f.conceptId,
                prerequisiteId: f.prerequisiteId,
                signal: f.signal,
              ),
        ],
        recommendations: [
          for (final r in recommendations) FeedbackRecommendation.from(r),
        ],
      ),
      profile: buildExplanationProfile(
        masteries: masteries,
        findings: findings,
        recommendations: recommendations,
        concepts: concepts,
      ),
    );
  }
  return out;
}

/// What happened when feedback was published.
class PublishResult {
  const PublishResult({
    required this.students,
    required this.profiles,
    required this.aiStudents,
    this.aiProblem,
    this.issueCounts = const {},
    this.guardRejected = 0,
    this.model,
  });

  /// Feedback documents written.
  final int students;

  /// Unique anonymous profiles (= explanations asked for).
  final int profiles;

  /// Students whose explanation is AI text that passed every guard.
  final int aiStudents;
  int get templateStudents => students - aiStudents;

  /// Set when AI was asked for but no model answered (templates used).
  final GenerationProblem? aiProblem;

  /// Per profile: why a model text was replaced by the template.
  final Map<ExplanationIssue, int> issueCounts;

  /// Profiles whose AI text failed at least one guard (template used).
  final int guardRejected;
  final String? model;
}

/// Thrown when feedback could not be saved. Feedback is then NOT released.
class FeedbackPublishException implements Exception {
  const FeedbackPublishException(this.cause);

  final Object cause;

  @override
  String toString() => 'FeedbackPublishException($cause)';
}

const _notAGuard = {ExplanationIssue.invalidAnswer, ExplanationIssue.missing};

class FeedbackPublisher {
  FeedbackPublisher({
    required this.content,
    required this.sessions,
    this.explainer,
  });

  final ContentRepository content;
  final SessionRepository sessions;

  /// Null when AI is not available (e.g. the offline demo mode).
  final FeedbackExplainer? explainer;

  /// Computes, explains, saves every document and only then releases
  /// feedback. If [useAi] is false, or AI fails, the template is used.
  /// Throws [FeedbackPublishException] if reading or saving failed; nothing
  /// is released then.
  Future<PublishResult> publish(Session session, {bool useAi = false}) async {
    final Map<String, ComputedFeedback> computed;
    final List<Concept> concepts;
    final List<Resource> resources;
    try {
      final responses = await sessions.watchResponses(session.id).first;
      final questions = await content.questionsForSession(
        session.courseId,
        session.questions,
      );
      final keys = await content.answerKeys(session.courseId);
      concepts = await content.listConcepts(session.courseId);
      resources = await content.listResources(session.courseId);
      computed = computeFeedback(
        responses: responses,
        questions: [for (final q in questions) q.question],
        keys: keys,
        concepts: concepts,
        resources: resources,
      );
    } catch (e) {
      throw FeedbackPublishException(e);
    }

    final groups = groupProfiles({
      for (final e in computed.entries) e.key: e.value.profile,
    });

    ExplainerAnswer? answer;
    GenerationProblem? aiProblem;
    final ai = explainer;
    if (useAi && ai != null && groups.profiles.isNotEmpty) {
      try {
        answer = await ai.explain(groups.profiles);
      } on QuestionGenerationException catch (e) {
        aiProblem = e.problem;
      } catch (_) {
        aiProblem = GenerationProblem.unknown;
      }
    }
    final batch = resolveExplanations(
      profiles: groups.profiles,
      modelAnswer: answer?.text,
      courseConcepts: concepts,
      courseResources: resources,
    );

    var aiStudents = 0;
    final documents = <String, StudentFeedback>{};
    for (final e in computed.entries) {
      final outcome = batch.byProfile[groups.profileIdOf[e.key]]!;
      if (outcome.fromAi) aiStudents++;
      final f = e.value.feedback;
      documents[e.key] = StudentFeedback(
        language: f.language,
        concepts: f.concepts,
        hints: f.hints,
        recommendations: f.recommendations,
        explanation: FeedbackExplanation(
          text: outcome.text,
          source:
              outcome.fromAi ? ExplanationSource.ai : ExplanationSource.template,
          model: outcome.fromAi ? answer?.model : null,
        ),
      );
    }

    try {
      // Order matters: every document first, then release.
      await sessions.saveFeedback(session.id, documents);
      await sessions.releaseFeedback(session.id);
    } catch (e) {
      throw FeedbackPublishException(e);
    }
    return PublishResult(
      students: documents.length,
      profiles: groups.profiles.length,
      aiStudents: aiStudents,
      aiProblem: aiProblem,
      issueCounts: batch.issueCounts,
      guardRejected: batch.byProfile.values
          .where((o) => o.issues.any((i) => !_notAGuard.contains(i)))
          .length,
      model: batch.aiCount > 0 ? answer?.model : null,
    );
  }
}
