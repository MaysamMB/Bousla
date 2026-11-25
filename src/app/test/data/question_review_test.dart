import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/question_review.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

OptionView _o(String id, String ar, String en) =>
    OptionView(id: id, text: LocalizedText(ar: ar, en: en));

QuestionDraft _validDraft({String? id}) => QuestionDraft(
  id: id,
  conceptIds: const ['primary_key'],
  prompt: const LocalizedText(
    ar: 'هل يقبل المفتاح الأساسي القيمة الفارغة؟',
    en: 'Can a primary key be NULL?',
  ),
  options: [_o('a', 'نعم', 'Yes'), _o('b', 'لا', 'No')],
  correctOptionId: 'b',
);

QuestionView _find(List<QuestionView> qs, String id) =>
    qs.where((q) => q.id == id).single;

void main() {
  group('validateDraft', () {
    const concepts = {'primary_key'};

    test('accepts a complete bilingual draft', () {
      expect(validateDraft(_validDraft(), concepts), isEmpty);
    });

    test('a question written in one language (same text twice) is valid',
        () {
      final draft = QuestionDraft(
        conceptIds: const ['primary_key'],
        prompt: const LocalizedText(
          ar: 'Can a primary key be NULL?',
          en: 'Can a primary key be NULL?',
        ),
        options: [_o('a', 'Yes', 'Yes'), _o('b', 'No', 'No')],
        correctOptionId: 'b',
      );
      expect(validateDraft(draft, concepts), isEmpty);
    });

    test('reports every problem it finds', () {
      final draft = QuestionDraft(
        conceptIds: const ['nope'],
        prompt: const LocalizedText(ar: 'Primary key?', en: ''),
        options: [_o('a', 'نعم', ''), _o('a', 'لا', 'No')],
        correctOptionId: 'z',
      );
      expect(
        validateDraft(draft, concepts),
        containsAll([
          DraftProblem.promptArabicHasNoArabicLetters,
          DraftProblem.promptEnglishMissing,
          DraftProblem.optionTextMissing,
          DraftProblem.duplicateOptionIds,
          DraftProblem.correctOptionMissing,
          DraftProblem.unknownConcept,
        ]),
      );
    });

    test('needs two options, a concept and a correct answer', () {
      final draft = QuestionDraft(
        conceptIds: const [],
        prompt: const LocalizedText(ar: 'سؤال؟', en: 'Question?'),
        options: [_o('a', 'نعم', 'Yes')],
        correctOptionId: null,
      );
      expect(
        validateDraft(draft, concepts),
        containsAll([
          DraftProblem.tooFewOptions,
          DraftProblem.conceptMissing,
          DraftProblem.correctOptionMissing,
        ]),
      );
    });

    test('code-only option text is allowed in both languages', () {
      final draft = QuestionDraft(
        conceptIds: const ['primary_key'],
        prompt: const LocalizedText(ar: 'أي عمود؟', en: 'Which column?'),
        options: [_o('a', 'student_id', 'student_id'), _o('b', 'gpa', 'gpa')],
        correctOptionId: 'a',
      );
      expect(validateDraft(draft, concepts), isEmpty);
    });
  });

  test('nextOptionId skips used letters', () {
    expect(nextOptionId(['a', 'b']), 'c');
    expect(nextOptionId(['a', 'c']), 'b');
    expect(nextOptionId([]), 'a');
  });

  group('InMemoryContentRepository review', () {
    late InMemoryContentRepository repo;

    setUp(() => repo = InMemoryContentRepository());

    test('AI drafts wait for review and are hidden from students', () async {
      final all = await repo.listQuestions(_course, approvedOnly: false);
      final drafts = all.where((q) => q.source == ContentSource.aiDraft);
      expect(drafts.map((q) => q.id), containsAll(['db_rm_001', 'db_rm_002']));
      expect(
        drafts.every((q) => q.status == ReviewStatus.pendingReview),
        isTrue,
      );
      final forStudents = await repo.listQuestions(_course);
      expect(forStudents.map((q) => q.id), isNot(contains('db_rm_001')));
    });

    test('approving one draft makes it available to students', () async {
      await repo.setQuestionsStatus(_course, [
        'db_rm_001',
      ], ReviewStatus.approved);
      final forStudents = await repo.listQuestions(_course);
      expect(forStudents.map((q) => q.id), contains('db_rm_001'));
      expect(forStudents.map((q) => q.id), isNot(contains('db_rm_002')));
    });

    test('rejecting several keeps them, with the reason', () async {
      await repo.setQuestionsStatus(
        _course,
        ['db_rm_001', 'db_rm_002'],
        ReviewStatus.rejected,
        reason: RejectionReason.unclear,
      );
      final all = await repo.listQuestions(_course, approvedOnly: false);
      for (final id in ['db_rm_001', 'db_rm_002']) {
        final q = _find(all, id);
        expect(q.status, ReviewStatus.rejected);
        expect(q.rejectionReason, RejectionReason.unclear);
      }
    });

    test('restoring a rejected question clears the reason', () async {
      await repo.setQuestionsStatus(
        _course,
        ['db_rm_001'],
        ReviewStatus.rejected,
        reason: RejectionReason.incorrect,
      );
      await repo.setQuestionsStatus(_course, [
        'db_rm_001',
      ], ReviewStatus.pendingReview);
      final q = _find(
        await repo.listQuestions(_course, approvedOnly: false),
        'db_rm_001',
      );
      expect(q.status, ReviewStatus.pendingReview);
      expect(q.rejectionReason, isNull);
    });

    test('a reason given when approving is not kept', () async {
      await repo.setQuestionsStatus(
        _course,
        ['db_rm_001'],
        ReviewStatus.approved,
        reason: RejectionReason.other,
      );
      final q = _find(await repo.listQuestions(_course), 'db_rm_001');
      expect(q.rejectionReason, isNull);
    });

    test('adding a question by hand', () async {
      final saved = await repo.saveQuestion(
        _course,
        _validDraft(),
        status: ReviewStatus.approved,
      );
      expect(saved.source, ContentSource.instructor);
      expect(saved.version, 1);
      expect(saved.edited, isFalse);
      expect((await repo.listQuestions(_course)).map((q) => q.id), contains(saved.id));
      final key = (await repo.answerKeys(_course)).singleWhere(
        (k) => k.questionId == saved.id,
      );
      expect(key.correctOptionId, 'b');
    });

    test('a new question without a status waits for review', () async {
      final saved = await repo.saveQuestion(_course, _validDraft());
      expect(saved.status, ReviewStatus.pendingReview);
    });

    test('editing an AI draft changes it in place and marks it edited', () async {
      final original = _find(
        await repo.listQuestions(_course, approvedOnly: false),
        'db_rm_001',
      );
      final draft = QuestionDraft.fromQuestion(original, 'd');
      final saved = await repo.saveQuestion(
        _course,
        QuestionDraft(
          id: draft.id,
          conceptIds: draft.conceptIds,
          prompt: const LocalizedText(
            ar: 'ما اسم الجدول في النموذج العلائقي؟',
            en: 'What is a table called in the relational model?',
          ),
          options: draft.options,
          correctOptionId: 'd',
        ),
      );
      expect(saved.version, 1);
      expect(saved.edited, isTrue);
      expect(saved.status, ReviewStatus.pendingReview);
      final all = await repo.listQuestions(_course, approvedOnly: false);
      expect(all.where((q) => q.id == 'db_rm_001'), hasLength(1));
    });

    test('saving an AI draft unchanged does not mark it edited', () async {
      final original = _find(
        await repo.listQuestions(_course, approvedOnly: false),
        'db_rm_002',
      );
      final saved = await repo.saveQuestion(
        _course,
        QuestionDraft.fromQuestion(original, 'a'),
        status: ReviewStatus.approved,
      );
      expect(saved.edited, isFalse);
      expect(saved.status, ReviewStatus.approved);
      expect(saved.version, 1);
    });

    test(
      'editing an approved question creates a new version and keeps the old one for sessions',
      () async {
        final original = _find(await repo.listQuestions(_course), 'db_pk_001');
        final draft = QuestionDraft.fromQuestion(original, 'a');
        final saved = await repo.saveQuestion(
          _course,
          QuestionDraft(
            id: draft.id,
            conceptIds: draft.conceptIds,
            prompt: draft.prompt,
            options: draft.options,
            correctOptionId: 'b',
          ),
        );
        expect(saved.version, 2);
        expect(saved.status, ReviewStatus.approved);

        final latest = _find(await repo.listQuestions(_course), 'db_pk_001');
        expect(latest.version, 2);

        final keys = await repo.answerKeys(_course);
        expect(
          keys
              .singleWhere(
                (k) => k.questionId == 'db_pk_001' && k.questionVersion == 1,
              )
              .correctOptionId,
          'a',
        );
        expect(
          keys
              .singleWhere(
                (k) => k.questionId == 'db_pk_001' && k.questionVersion == 2,
              )
              .correctOptionId,
          'b',
        );

        final old = await repo.questionsForSession(_course, const [
          QuestionRef('db_pk_001', 1),
        ]);
        expect(old.single.version, 1);
      },
    );

    test('questionsForSession skips questions rejected later', () async {
      await repo.setQuestionsStatus(_course, [
        'db_pk_002',
      ], ReviewStatus.rejected);
      final qs = await repo.questionsForSession(_course, const [
        QuestionRef('db_pk_001', 1),
        QuestionRef('db_pk_002', 1),
      ]);
      expect(qs.map((q) => q.id), ['db_pk_001']);
    });

    test('invalid drafts are refused', () async {
      expect(
        () => repo.saveQuestion(
          _course,
          QuestionDraft(
            conceptIds: const ['primary_key'],
            prompt: const LocalizedText(ar: '', en: 'Question?'),
            options: [_o('a', 'نعم', 'Yes'), _o('b', 'لا', 'No')],
            correctOptionId: 'a',
          ),
        ),
        throwsA(isA<InvalidDraftException>()),
      );
    });

    test('editing an unknown question fails', () async {
      expect(
        () => repo.saveQuestion(_course, _validDraft(id: 'missing')),
        throwsArgumentError,
      );
    });
  });

  test('aiReviewStats counts decisions on AI drafts only', () async {
    final repo = InMemoryContentRepository();
    final first = _find(
      await repo.listQuestions(_course, approvedOnly: false),
      'db_rm_001',
    );
    await repo.saveQuestion(
      _course,
      QuestionDraft(
        id: first.id,
        conceptIds: first.conceptIds,
        prompt: const LocalizedText(
          ar: 'ما اسم الجدول في النموذج العلائقي؟',
          en: 'What is a table called in the relational model?',
        ),
        options: first.options,
        correctOptionId: 'd',
      ),
      status: ReviewStatus.approved,
    );
    await repo.setQuestionsStatus(
      _course,
      ['db_rm_002'],
      ReviewStatus.rejected,
      reason: RejectionReason.translation,
    );
    await repo.saveQuestion(_course, _validDraft(), status: ReviewStatus.approved);

    final stats = aiReviewStats(
      await repo.listQuestions(_course, approvedOnly: false),
    );
    expect(stats.total, 2);
    expect(stats.approvedEdited, 1);
    expect(stats.approvedAsIs, 0);
    expect(stats.rejected, 1);
    expect(stats.pending, 0);
    expect(stats.reviewed, 2);
    expect(stats.rejectionReasons, {RejectionReason.translation: 1});
  });

  group('hidden answer languages', () {
    late InMemoryContentRepository repo;

    setUp(() => repo = InMemoryContentRepository());

    Future<QuestionView> latest(String id) async =>
        _find(await repo.listQuestions(_course, approvedOnly: false), id);

    test('toggleHiddenLanguage keeps at most one language hidden', () {
      expect(toggleHiddenLanguage({}, Language.ar, true), {Language.ar});
      expect(toggleHiddenLanguage({Language.ar}, Language.en, true), {
        Language.en,
      });
      expect(toggleHiddenLanguage({Language.ar}, Language.ar, false), isEmpty);
      expect(toggleHiddenLanguage({Language.ar}, Language.en, false), {
        Language.ar,
      });
    });

    test('a student using a hidden language sees the other one', () async {
      await repo.setOptionLanguageHidden(
        _course,
        ['db_pk_001'],
        Language.ar,
        hidden: true,
      );
      final q = await latest('db_pk_001');
      expect(q.optionLanguageFor(Language.ar), Language.en);
      expect(q.optionLanguageFor(Language.en), Language.en);
      final other = await latest('db_pk_002');
      expect(other.optionLanguageFor(Language.ar), Language.ar);
    });

    test('hiding English shows Arabic again', () async {
      await repo.setOptionLanguageHidden(
        _course,
        ['db_pk_001'],
        Language.ar,
        hidden: true,
      );
      await repo.setOptionLanguageHidden(
        _course,
        ['db_pk_001'],
        Language.en,
        hidden: true,
      );
      expect((await latest('db_pk_001')).hiddenOptionLanguages, {Language.en});
    });

    test('is not a content change: same version, not edited', () async {
      await repo.setOptionLanguageHidden(
        _course,
        ['db_rm_001', 'db_pk_001'],
        Language.ar,
        hidden: true,
      );
      final draft = await latest('db_rm_001');
      expect(draft.version, 1);
      expect(draft.edited, isFalse);
      expect(draft.hiddenOptionLanguages, {Language.ar});
      expect((await latest('db_pk_001')).version, 1);
    });

    test('applies to the version a running session uses', () async {
      final original = await latest('db_pk_001');
      final draft = QuestionDraft.fromQuestion(original, 'a');
      await repo.saveQuestion(
        _course,
        QuestionDraft(
          id: draft.id,
          conceptIds: draft.conceptIds,
          prompt: draft.prompt,
          options: draft.options,
          correctOptionId: 'b',
        ),
      );
      await repo.setOptionLanguageHidden(
        _course,
        ['db_pk_001'],
        Language.ar,
        hidden: true,
      );
      final v1 = await repo.questionsForSession(_course, const [
        QuestionRef('db_pk_001', 1),
      ]);
      expect(v1.single.hiddenOptionLanguages, {Language.ar});
    });

    test('changing only the setting in the editor keeps the version', () async {
      final original = await latest('db_pk_001');
      final draft = QuestionDraft.fromQuestion(original, 'a');
      final saved = await repo.saveQuestion(
        _course,
        QuestionDraft(
          id: draft.id,
          conceptIds: draft.conceptIds,
          prompt: draft.prompt,
          options: draft.options,
          correctOptionId: draft.correctOptionId,
          hiddenOptionLanguages: const {Language.en},
        ),
      );
      expect(saved.version, 1);
      expect(saved.hiddenOptionLanguages, {Language.en});
    });

    test('answers are still required in the hidden language', () {
      final draft = QuestionDraft(
        conceptIds: const ['primary_key'],
        prompt: const LocalizedText(ar: 'سؤال؟', en: 'Question?'),
        options: [_o('a', '', 'Yes'), _o('b', '', 'No')],
        correctOptionId: 'a',
        hiddenOptionLanguages: const {Language.ar},
      );
      expect(
        validateDraft(draft, {'primary_key'}),
        contains(DraftProblem.optionTextMissing),
      );
    });

    test('both languages cannot be hidden', () {
      final draft = QuestionDraft(
        conceptIds: const ['primary_key'],
        prompt: const LocalizedText(ar: 'سؤال؟', en: 'Question?'),
        options: [_o('a', 'نعم', 'Yes'), _o('b', 'لا', 'No')],
        correctOptionId: 'a',
        hiddenOptionLanguages: const {Language.ar, Language.en},
      );
      expect(
        validateDraft(draft, {'primary_key'}),
        contains(DraftProblem.allOptionLanguagesHidden),
      );
    });

    test('reads hidden_option_languages from JSON', () {
      final q = QuestionView.fromJson({
        'id': 'q',
        'version': 1,
        'concept_ids': ['primary_key'],
        'prompt': {'ar': 'سؤال؟', 'en': 'Question?'},
        'options': [
          {
            'id': 'a',
            'text': {'ar': 'أ', 'en': 'A'},
          },
        ],
        'hidden_option_languages': ['en'],
      });
      expect(q.hiddenOptionLanguages, {Language.en});
    });
  });
}
