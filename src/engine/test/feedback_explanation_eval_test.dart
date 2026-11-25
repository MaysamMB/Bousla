// Evaluation harness for AI level 2 (docs/architecture.md §9): 20 synthetic
// profiles, ONE mocked model answer, and the guards' real accept/reject
// counts. The mocked answer is a fixture written for this test: 12 entries
// written to be acceptable and 8 with typical model mistakes. The rate
// printed here therefore measures the guards against this fixture, NOT the
// quality of Gemini; a live run is still needed for that.
import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'support/explanation_eval_cases.dart';

final _course = evalCourse;
final _resources = evalResources;
final _patterns = evalPatterns;
const _twice = evalTwice;
List<Response> _answers(String student, EvalPattern p, Language lang) =>
    evalAnswers(student, p, lang);
Map<String, ExplanationProfile> _profiles(List<Response> responses) =>
    evalProfiles(responses);

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
      for (final e in patternOf.entries) e.value: groups.profileOf(e.key),
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
