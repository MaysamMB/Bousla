// Evaluation harness for AI level 2 (docs/architecture.md §9): 20 synthetic
// profiles, ONE mocked model answer, and the guards' real accept/reject
// counts. The mocked answer is a fixture written for this test: 12 entries
// written to be acceptable and 8 with typical model mistakes. The rate
// printed here therefore measures the guards against this fixture, NOT the
// quality of Gemini; a live run is still needed for that.
import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

LocalizedText _t(String ar, String en) => LocalizedText(ar: ar, en: en);

/// The real Database Systems concepts (data/courses/database-systems).
final _course = [
  Concept(id: 'relational_model', name: _t('النموذج العلائقي', 'Relational Model')),
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
const _session = ['primary_key', 'foreign_key', 'sql_select', 'sql_join'];
const _covered = ['relational_model', ..._session];

final _questions = [
  for (final c in _session)
    for (var n = 1; n <= 4; n++)
      Question(
          id: '${c}_$n',
          version: 1,
          conceptIds: [c],
          optionIds: ['a', 'b', 'c', 'd']),
];
final _keys = [
  for (final q in _questions)
    AnswerKey(questionId: q.id, questionVersion: 1, correctOptionId: 'a'),
];

final _resources = [
  for (final c in _session)
    Resource(
      id: 'res_${c}_practice',
      conceptIds: [c],
      type: ResourceType.activity,
      language: ResourceLanguage.both,
      title: _t('تدريب: ${_course.firstWhere((x) => x.id == c).name.ar}',
          'Practice: ${_course.firstWhere((x) => x.id == c).name.en}'),
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
typedef _Pattern = List<(int, int)>;

/// 20 distinct educational patterns.
final List<(String, _Pattern)> _patterns = [
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
const _twice = {0, 2, 6, 9, 12, 16};

List<Response> _answers(String student, _Pattern p, Language lang) => [
      for (var i = 0; i < _session.length; i++)
        for (var n = 1; n <= p[i].$1; n++)
          Response(
            participantId: student,
            questionId: '${_session[i]}_$n',
            questionVersion: 1,
            selectedOptionId: n <= p[i].$2 ? 'a' : 'b',
            displayLanguage: lang,
          ),
    ];

/// The instructor app's pipeline, per student.
Map<String, ExplanationProfile> _profiles(List<Response> responses) {
  final scored =
      scoreResponses(responses: responses, questions: _questions, keys: _keys)
          .scored;
  final evidence = evidenceByParticipant(scored: scored, conceptIds: _covered);
  return {
    for (final e in evidence.entries)
      e.key: () {
        final masteries = estimateAll(e.value);
        return buildExplanationProfile(
          masteries: masteries,
          findings:
              analyzePrerequisites(masteries: masteries, concepts: _course),
          recommendations: recommend(
            masteries: masteries,
            concepts: _course,
            resources: _resources,
            preferredLanguage: Language.ar,
          ),
          concepts: _course,
        );
      }(),
  };
}

/// What the mocked model "answered" for profile number [i] (0-based).
/// Null: the entry is missing from the answer.
Map<String, String>? _fixture(int i, ExplanationProfile p) {
  final focus = p.recommendations.isNotEmpty
      ? p.concept(p.recommendations.first.conceptId)!
      : p.concepts.first;
  final ok = {
    'text_ar': 'شكرًا لمشاركتك في الجلسة. قد يساعدك التركيز على '
        '${focus.name.ar} في خطوتك التالية.',
    'text_en': 'Thank you for taking part in the session. Focusing on '
        '${focus.name.en} next may help.',
  };
  return switch (i) {
    // Guard 1: a course concept that is not in this profile.
    2 => {...ok, 'text_en': 'Normalization may also help you here.'},
    5 => {...ok, 'text_ar': 'قد يساعدك أيضًا مراجعة التطبيع.'},
    // Guard 2: an invented link.
    8 => {
        ...ok,
        'text_en': 'Try https://www.w3schools.com/sql/ for more practice.',
      },
    // Guard 3: English in the Arabic field.
    11 => {...ok, 'text_ar': ok['text_en']!},
    // Guard 4: definitive or discouraging wording.
    14 => {...ok, 'text_en': 'You have a gap in ${focus.name.en}.'},
    17 => {...ok, 'text_ar': 'مستواك ضعيف في ${focus.name.ar}.'},
    // Guard 5: far too long.
    19 => {...ok, 'text_en': '${ok['text_en']} ' * 8},
    // Missing from the answer.
    16 => null,
    _ => ok,
  };
}

void main() {
  test('20 synthetic profiles through one mocked request', () {
    final responses = <Response>[];
    final patternOf = <String, int>{};
    for (var i = 0; i < _patterns.length; i++) {
      final student = 'student_${i}_a';
      responses.addAll(_answers(student, _patterns[i].$2, Language.ar));
      patternOf[student] = i;
      if (_twice.contains(i)) {
        final other = 'student_${i}_b';
        responses.addAll(_answers(other, _patterns[i].$2, Language.en));
        patternOf[other] = i;
      }
    }
    final byStudent = _profiles(responses);
    expect(byStudent, hasLength(26));

    // Grouping: 26 students, 20 unique profiles; same pattern → same
    // profile whatever the answer language; different pattern → different.
    final groups = groupProfiles(byStudent);
    expect(groups.profiles, hasLength(20));
    for (final a in patternOf.keys) {
      for (final b in patternOf.keys) {
        expect(
          groups.profileIdOf[a] == groups.profileIdOf[b],
          patternOf[a] == patternOf[b],
          reason: '$a vs $b',
        );
      }
    }

    // Exactly one request, holding no student ID.
    final prompt = buildFeedbackExplanationPrompt(groups.profiles);
    for (final s in patternOf.keys) {
      expect(prompt, isNot(contains(s)));
    }

    // The fixture is indexed by pattern, so find each pattern's profile.
    final profileOfPattern = {
      for (final e in patternOf.entries)
        e.value: groups.profileOf(e.key),
    };
    final answer = jsonEncode([
      for (var i = 0; i < _patterns.length; i++)
        if (_fixture(i, profileOfPattern[i]!) case final f?)
          {'profile_id': profileOfPattern[i]!.id, ...f},
    ]);
    final batch = resolveExplanations(
      profiles: groups.profiles,
      modelAnswer: answer,
      courseConcepts: _course,
      courseResources: _resources,
    );

    // Real counts from the guards.
    final rejected = {
      for (var i = 0; i < _patterns.length; i++)
        if (!batch.byProfile[profileOfPattern[i]!.id]!.fromAi)
          i: batch.byProfile[profileOfPattern[i]!.id]!.issues,
    };
    final accepted = batch.aiCount;
    // ignore: avoid_print
    print('AI level 2 harness: $accepted of ${groups.profiles.length} '
        'mocked explanations passed all guards '
        '(${(100 * accepted / groups.profiles.length).toStringAsFixed(0)}%).');
    for (final e in rejected.entries) {
      // ignore: avoid_print
      print('  rejected #${e.key + 1} (${_patterns[e.key].$1}): '
          '${e.value.map((i) => i.name).join(', ')}');
    }

    expect(accepted, 12);
    expect(rejected.keys.toSet(), {2, 5, 8, 11, 14, 16, 17, 19});
    expect(rejected[2], [ExplanationIssue.unknownConcept]);
    expect(rejected[5], [ExplanationIssue.unknownConcept]);
    expect(rejected[8], [ExplanationIssue.unapprovedResource]);
    expect(rejected[11], [ExplanationIssue.wrongLanguage]);
    expect(rejected[14], [ExplanationIssue.forbiddenWording]);
    expect(rejected[17], [ExplanationIssue.forbiddenWording]);
    expect(rejected[19], [ExplanationIssue.tooLong]);
    expect(rejected[16], [ExplanationIssue.missing]);

    // Fallback: every rejected profile gets the template, which passes all
    // guards; every student gets their own profile's text.
    for (final e in batch.byProfile.entries) {
      final p = groups.profiles.firstWhere((x) => x.id == e.key);
      if (!e.value.fromAi) {
        expect(e.value.text.en, templateExplanation(p).en);
      }
      expect(
        checkExplanation(e.value.text,
            profile: p, courseConcepts: _course, courseResources: _resources),
        isEmpty,
      );
    }
    for (final s in patternOf.keys) {
      final p = groups.profileOf(s);
      final outcome = batch.byProfile[p.id]!;
      final expected = _fixture(patternOf[s]!, p);
      if (outcome.fromAi) expect(outcome.text.en, expected!['text_en']);
    }
  });
}
