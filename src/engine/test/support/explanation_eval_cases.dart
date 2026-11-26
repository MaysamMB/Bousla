// The 20 synthetic student profiles of the AI level 2 evaluation
// (docs/architecture.md §9), shared by the mocked guard test
// (feedback_explanation_eval_test.dart) and the real-Gemini evaluation
// (tool/gemini_explanation_eval.dart), so both measure the same cases.
// Pure Dart: the instructor app's engine pipeline, no network.
import 'package:bousla_engine/bousla_engine.dart';

LocalizedText _t(String ar, String en) => LocalizedText(ar: ar, en: en);

/// The real Database Systems concepts (data/courses/database-systems).
final evalCourse = [
  Concept(
      id: 'relational_model', name: _t('النموذج العلائقي', 'Relational Model')),
  Concept(
      id: 'primary_key',
      name: _t('المفتاح الأساسي', 'Primary Key'),
      prerequisites: ['relational_model']),
  Concept(
      id: 'foreign_key',
      name: _t('المفتاح الخارجي', 'Foreign Key'),
      prerequisites: ['primary_key']),
  Concept(
      id: 'er_modeling',
      name: _t('نمذجة الكيانات والعلاقات', 'Entity-Relationship Modeling'),
      prerequisites: ['relational_model']),
  Concept(
      id: 'functional_dependency',
      name: _t('الاعتمادية الوظيفية', 'Functional Dependency'),
      prerequisites: ['primary_key']),
  Concept(
      id: 'normalization',
      name: _t('التطبيع', 'Normalization'),
      prerequisites: ['functional_dependency']),
  Concept(
      id: 'sql_select',
      name: _t('استعلامات SELECT الأساسية', 'Basic SELECT Queries'),
      prerequisites: ['relational_model']),
  Concept(
      id: 'sql_join',
      name: _t('ربط الجداول (JOIN)', 'Joins'),
      prerequisites: ['sql_select', 'foreign_key']),
  Concept(
      id: 'sql_aggregation',
      name: _t('التجميع (GROUP BY)', 'Aggregation (GROUP BY)'),
      prerequisites: ['sql_select']),
  Concept(
      id: 'transactions_acid',
      name: _t('المعاملات وخصائص ACID', 'Transactions and ACID'),
      prerequisites: ['relational_model']),
];

/// The session asks about these; their direct prerequisites are included.
const evalSessionConcepts = [
  'primary_key',
  'foreign_key',
  'sql_select',
  'sql_join'
];
const evalCoveredConcepts = ['relational_model', ...evalSessionConcepts];

final evalQuestions = [
  for (final c in evalSessionConcepts)
    for (var n = 1; n <= 4; n++)
      Question(
          id: '${c}_$n',
          version: 1,
          conceptIds: [c],
          optionIds: ['a', 'b', 'c', 'd']),
];
final evalKeys = [
  for (final q in evalQuestions)
    AnswerKey(questionId: q.id, questionVersion: 1, correctOptionId: 'a'),
];

final evalResources = [
  for (final c in evalSessionConcepts)
    Resource(
      id: 'res_${c}_practice',
      conceptIds: [c],
      type: ResourceType.activity,
      language: ResourceLanguage.both,
      title: _t('تدريب: ${evalCourse.firstWhere((x) => x.id == c).name.ar}',
          'Practice: ${evalCourse.firstWhere((x) => x.id == c).name.en}'),
    ),
  Resource(
    id: 'res_join_unreviewed',
    conceptIds: ['sql_join'],
    type: ResourceType.link,
    language: ResourceLanguage.en,
    title: _t('مقال غير معتمد', 'Unreviewed join article'),
    url: 'https://unreviewed.example.org/join',
    status: ReviewStatus.pendingReview,
  ),
];

/// (attempts, correct) for primary_key, foreign_key, sql_select, sql_join.
typedef EvalPattern = List<(int, int)>;

/// 20 distinct educational patterns.
final List<(String, EvalPattern)> evalPatterns = [
  ('strong everywhere', [(3, 3), (3, 3), (3, 3), (3, 3)]),
  ('strong, more answers', [(4, 4), (3, 3), (4, 4), (3, 3)]),
  ('difficulty everywhere', [(2, 0), (2, 0), (2, 0), (2, 0)]),
  ('difficulty in keys', [(2, 0), (3, 1), (2, 2), (2, 1)]),
  ('insufficient evidence', [(1, 1), (1, 0), (0, 0), (0, 0)]),
  ('insufficient evidence, other mix', [(1, 0), (0, 0), (1, 1), (0, 0)]),
  ('emerging everywhere', [(2, 1), (2, 1), (2, 1), (2, 1)]),
  ('emerging, more answers', [(3, 2), (3, 2), (2, 1), (3, 2)]),
  ('weak prerequisite: not enough evidence', [(1, 0), (2, 0), (3, 3), (2, 0)]),
  ('weak prerequisite: possible gap', [(2, 0), (2, 0), (3, 3), (2, 0)]),
  ('difficulty, prerequisite mastered', [(3, 3), (2, 0), (3, 3), (2, 0)]),
  ('difficulty, prerequisite emerging', [(2, 1), (2, 0), (2, 0), (2, 0)]),
  ('SELECT gap under JOIN', [(3, 3), (3, 3), (2, 0), (2, 0)]),
  ('mixed 1', [(3, 3), (2, 1), (3, 2), (2, 0)]),
  ('mixed 2', [(2, 0), (3, 3), (2, 1), (3, 3)]),
  ('mixed with unanswered', [(3, 3), (1, 1), (2, 1), (0, 0)]),
  ('mixed, four answers each', [(4, 3), (4, 1), (4, 4), (4, 2)]),
  ('all right but too few answers', [(2, 2), (2, 2), (2, 2), (2, 2)]),
  ('mixed 3', [(3, 1), (3, 3), (3, 0), (3, 3)]),
  ('mixed 4', [(4, 4), (2, 0), (1, 1), (2, 0)]),
];

/// Patterns answered by a second student, in the other language.
const evalTwice = {0, 2, 6, 9, 12, 16};

List<Response> evalAnswers(String student, EvalPattern p, Language lang) => [
      for (var i = 0; i < evalSessionConcepts.length; i++)
        for (var n = 1; n <= p[i].$1; n++)
          Response(
            participantId: student,
            questionId: '${evalSessionConcepts[i]}_$n',
            questionVersion: 1,
            selectedOptionId: n <= p[i].$2 ? 'a' : 'b',
            displayLanguage: lang,
          ),
    ];

/// The instructor app's pipeline, per student.
Map<String, ExplanationProfile> evalProfiles(List<Response> responses) {
  final scored = scoreResponses(
          responses: responses, questions: evalQuestions, keys: evalKeys)
      .scored;
  final evidence =
      evidenceByParticipant(scored: scored, conceptIds: evalCoveredConcepts);
  return {
    for (final e in evidence.entries)
      e.key: () {
        final masteries = estimateAll(e.value);
        return buildExplanationProfile(
          masteries: masteries,
          findings:
              analyzePrerequisites(masteries: masteries, concepts: evalCourse),
          recommendations: recommend(
            masteries: masteries,
            concepts: evalCourse,
            resources: evalResources,
            preferredLanguage: Language.ar,
          ),
          concepts: evalCourse,
        );
      }(),
  };
}

/// The 26 students of the evaluation (6 patterns answered twice, once in
/// each language) and which pattern each one answered.
(List<Response>, Map<String, int>) evalStudents() {
  final responses = <Response>[];
  final patternOf = <String, int>{};
  for (var i = 0; i < evalPatterns.length; i++) {
    final student = 'student_${i}_a';
    responses.addAll(evalAnswers(student, evalPatterns[i].$2, Language.ar));
    patternOf[student] = i;
    if (evalTwice.contains(i)) {
      final other = 'student_${i}_b';
      responses.addAll(evalAnswers(other, evalPatterns[i].$2, Language.en));
      patternOf[other] = i;
    }
  }
  return (responses, patternOf);
}
