import 'package:bousla_app/features/instructor/sessions/teaching_actions.dart';
import 'package:bousla_app/features/instructor/sessions/teaching_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const review = TeachingActionKind.reviewConcept;
  test('valid allowlisted choice is accepted', () {
    expect(parseTeachingStrategy('{"strategy":"peerExplanation"}', review),
        TeachingStrategy.peerExplanation);
  });
  test('assessment cannot be turned into a diagnosis or a review tactic', () {
    expect(parseTeachingStrategy('{"strategy":"contrastExamples"}',
        TeachingActionKind.assessFurther), isNull);
  });
  test('unknown tactic, prose, extra fields and malformed JSON are rejected', () {
    for (final raw in ['{"strategy":"invented"}', 'Class failed',
      '{"strategy":"peerExplanation","score":42}', '{', '[]',
      '{"strategy":42}', List.filled(257, 'x').join()]) {
      expect(parseTeachingStrategy(raw, review), isNull);
    }
  });
  test('all action kinds have distinct allowed strategies', () {
    expect(TeachingActionKind.values.expand(allowedStrategies).toSet().length, 6);
  });
  test('prompt contains course concept and action but no student data fields', () {
    final prompt = teachingStrategyPrompt(kind: review, conceptName: 'Primary Key');
    expect(prompt, contains('Primary Key'));
    expect(prompt, contains('reviewConcept'));
    for (final field in ['participantId', 'sessionId', 'affectedCount',
      'groupCount', 'rawAnswers']) {
      expect(prompt, isNot(contains(field)));
    }
  });
  test('successful selection is labelled AI', () async {
    final result = await resolveTeachingStrategy(kind: review, conceptName: 'PK',
        choose: (_) async => '{"strategy":"peerExplanation","example":"Compare a primary key with a foreign key.","question":"Which key references another table?"}');
    expect(result.aiSelected, isTrue);
    expect(result.strategy, TeachingStrategy.peerExplanation);
  });
  test('invalid response, exception and offline use same fallback', () async {
    for (final TeachingStrategyChooser? chooser in [null,
      (_) async => '{"strategy":"quickCheck"}',
      (_) async => throw StateError('offline')]) {
      final result = await resolveTeachingStrategy(kind: review,
        conceptName: 'PK', choose: chooser);
      expect(result.aiSelected, isFalse);
      expect(result.strategy, TeachingStrategy.contrastExamples);
    }
  });
  test('complete draft accepted; missing, invalid language or claims rejected', () {
    const valid = '{"strategy":"peerExplanation","example":"Compare a primary key with a foreign key.","question":"Which key references another table?"}';
    expect(parseTeachingDraft(valid, review, language: 'en')?.example,
        'Compare a primary key with a foreign key.');
    expect(parseTeachingDraft(valid, review, language: 'ar'), isNull);
    expect(parseTeachingDraft('{"strategy":"peerExplanation"}', review,
        language: 'en'), isNull);
    expect(parseTeachingDraft(valid.replaceFirst('Compare a primary key with a foreign key.',
        'The class failed: 75%.'), review, language: 'en'), isNull);
    expect(parseTeachingDraft(valid.replaceFirst('Which key references another table?',
        'https://example.com'), review, language: 'en'), isNull);
  });
}
