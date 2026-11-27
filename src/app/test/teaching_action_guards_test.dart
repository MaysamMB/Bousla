// Instructor teaching action (AI level 2, instructor side): the engine picks
// the action from aggregated class results; the model may only choose an
// allowed tactic and draft an example and a question for the instructor.
// These tests cover the guards on that draft and the fallback. No real model
// call: a fake chooser answers.
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/features/instructor/sessions/teaching_actions.dart';
import 'package:bousla_app/features/instructor/sessions/teaching_strategy.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _review = TeachingActionKind.reviewConcept;

String _draft({
  String strategy = 'contrastExamples',
  String example =
      'Show one table with a valid primary key and one with duplicates, '
          'then compare them together.',
  String question = 'Which column could identify each row uniquely?',
}) =>
    '{"strategy":"$strategy","example":"$example","question":"$question"}';

TeachingDraft? _parse(String raw, {String language = 'en'}) =>
    parseTeachingDraft(raw, _review, language: language);

Future<TeachingStrategyResult> _resolve(
  TeachingStrategyChooser? choose, {
  String conceptName = 'Primary Key',
  String language = 'en',
}) =>
    resolveTeachingStrategy(
      kind: _review,
      conceptName: conceptName,
      choose: choose,
      language: language,
    );

void main() {
  group('valid AI teaching action', () {
    test(
        'English draft: accepted, labelled AI, with tactic, example and '
        'question', () async {
      final r = await _resolve((_) async => _draft());
      expect(r.aiSelected, isTrue);
      expect(r.strategy, TeachingStrategy.contrastExamples);
      expect(r.draft!.example, startsWith('Show one table'));
      expect(r.draft!.question, endsWith('uniquely?'));
    });

    test('Arabic draft is accepted in Arabic', () async {
      final r = await _resolve(
        (_) async => _draft(
          strategy: 'peerExplanation',
          example:
              'اطلب من كل طالبين شرح سبب اختيار المفتاح الأساسي لجدول الطلاب.',
          question: 'لماذا يجب أن يكون المفتاح الأساسي فريدًا؟',
        ),
        conceptName: 'المفتاح الأساسي',
        language: 'ar',
      );
      expect(r.aiSelected, isTrue);
      expect(r.strategy, TeachingStrategy.peerExplanation);
    });

    test('classroom instructions about students are not claims', () {
      for (final example in [
        'Ask some students to explain their choice of primary key.',
        'Have all students compare two tables before the discussion.',
      ]) {
        expect(_parse(_draft(example: example)), isNotNull, reason: example);
      }
    });
  });

  group('instructor-facing only', () {
    test(
        'the prompt is addressed to the instructor and holds no student '
        'data', () {
      final prompt =
          teachingStrategyPrompt(kind: _review, conceptName: 'Primary Key');
      expect(prompt, contains('for the instructor'));
      expect(prompt, contains('Do not assess students'));
      for (final field in ['participant', 'uid', 'affectedCount', 'score']) {
        expect(prompt, isNot(contains(field)));
      }
    });

    test('personal feedback to a student is rejected (EN and AR)', () {
      for (final example in [
        'Your answer shows a misunderstanding of primary keys.',
        'You failed to identify the primary key, so review it.',
        'Look at your score on primary keys first.',
      ]) {
        expect(_parse(_draft(example: example)), isNull, reason: example);
      }
      for (final example in [
        'إجابتك تدل على خلط في المفتاح الأساسي.',
        'مستواك في المفتاح الأساسي يحتاج مراجعة.',
      ]) {
        expect(
          _parse(
            _draft(example: example, question: 'لماذا يكون المفتاح فريدًا؟'),
            language: 'ar',
          ),
          isNull,
          reason: example,
        );
      }
    });
  });

  group('unsupported claims are never presented as facts', () {
    test('English claims about actual students are rejected', () {
      for (final example in [
        'Most students are confused about primary keys, so reteach them.',
        'Many of the students struggle with keys; start from scratch.',
        'The class failed this concept, so repeat the lecture.',
        'Half of your students cannot tell the keys apart.',
      ]) {
        expect(_parse(_draft(example: example)), isNull, reason: example);
      }
    });

    test('Arabic claims about actual students are rejected', () {
      for (final example in [
        'معظم الطلاب لا يفهمون المفتاح الأساسي، فأعد شرحه.',
        'أغلب الطلاب يخلطون بين المفتاحين.',
        'الصف ضعيف في المفاتيح، ابدأ من البداية.',
      ]) {
        expect(
          _parse(
            _draft(example: example, question: 'ما وظيفة المفتاح الأساسي؟'),
            language: 'ar',
          ),
          isNull,
          reason: example,
        );
      }
    });

    test('a rejected draft falls back to the rule tactic, not labelled AI',
        () async {
      final r = await _resolve(
        (_) async => _draft(
          example: 'Most students are confused about primary keys.',
        ),
      );
      expect(r.aiSelected, isFalse);
      expect(r.draft, isNull);
      expect(r.strategy, allowedStrategies(_review).first);
    });
  });

  group('invalid output and failures', () {
    test('malformed, prose, wrong tactic or extra fields: fallback', () async {
      for (final raw in [
        'Teach primary keys again.',
        '{',
        _draft(strategy: 'quickCheck'), // not allowed for reviewConcept
        '{"strategy":"contrastExamples","example":"Compare keys.",'
            '"question":"Why?","score":42}',
      ]) {
        final r = await _resolve((_) async => raw);
        expect(r.aiSelected, isFalse, reason: raw);
        expect(r.draft, isNull, reason: raw);
      }
    });

    test('AI or network failure: same deterministic fallback', () async {
      for (final error in [
        const QuestionGenerationException(GenerationProblem.busy),
        const QuestionGenerationException(GenerationProblem.dailyQuota),
        StateError('offline'),
      ]) {
        final r = await _resolve((_) async => throw error);
        expect(r.aiSelected, isFalse, reason: '$error');
        expect(r.strategy, TeachingStrategy.contrastExamples);
      }
    });
  });

  group('missing, incomplete or empty data', () {
    test('an empty concept name never reaches the model', () async {
      var calls = 0;
      final r = await _resolve(
        (_) async {
          calls++;
          return _draft();
        },
        conceptName: '  ',
      );
      expect(calls, 0);
      expect(r.aiSelected, isFalse);
    });

    test('no learning gaps, no data or too few students: no action', () {
      ClassInsights insights(List<ConceptClassSummary> concepts) =>
          ClassInsights(
            participantCount: 8,
            minGroupSize: 5,
            concepts: concepts,
            prerequisiteSignals: const [],
          );
      // Everyone fine: no gap, no action.
      final fine = const ConceptClassSummary(
        conceptId: 'pk',
        respondents: 8,
        suppressed: false,
        stateCounts: {MasteryState.demonstratedMastery: 8},
      );
      expect(
        prioritizeTeachingActions(insights([fine]), coveredConceptIds: {'pk'}),
        isEmpty,
      );
      // No data at all.
      expect(
        prioritizeTeachingActions(insights(const []), coveredConceptIds: {}),
        isEmpty,
      );
      // Too few respondents: hidden for privacy, no action either.
      final small = const ConceptClassSummary(
        conceptId: 'pk',
        respondents: 3,
        suppressed: true,
      );
      expect(
        prioritizeTeachingActions(insights([small]), coveredConceptIds: {'pk'}),
        isEmpty,
      );
    });
  });
}
